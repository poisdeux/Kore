#!/bin/bash

[ -z "${ANDROID_HOME}" ] && echo "ERROR: ANDROID_HOME variable not defined" && exit 1

export PATH=/bin/:/usr/bin:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools
EMULATOR_OPTS="-no-snapshot -gpu host"
POWEROFF_DEVICE=0
START_DEVICE=0
ENABLE_ANIMS=-1
CREATE_AVD=0
REMOVE_AVD=0
UNLOCK_AVD=0
AVD_NAME="test"
TARGET="android-27"
PORT=5556

function usage {
    echo "Usage: $0 -l | -[dpsloewctnr]..."
    echo
    echo "  -b      run device in daemon mode"
    echo "  -p      poweroff device"
    echo "  -s      start device in foreground"
    echo "  -l      list available virtual devices"
    echo "  -d      disable animations globally on device"
    echo "  -e      enable animations globally on device"
    echo "  -w      wipe data storage from device"
    echo "  -c      create new virtual device (avd)"
    echo "  -t      specify target name for new avd (default: ${TARGET})"
    echo "  -n      specify device name (default: ${AVD_NAME})"
    echo "  -u      port number for emulator (default: ${PORT})"
    echo "  -r      remove virtual device"
    echo "  -x      unlock device"
    echo
}

function kill_emulator {
    if ! ps -p $EMULATOR_PID > /dev/null 2>&1
    then
        return 1
    fi

    #we start asking nicely
    kill ${EMULATOR_PID}

    COUNT=10
    while ps -p $EMULATOR_PID > /dev/null 2>&1 && [ $((COUNT--)) -gt 0 ]
    do
        sleep 0.2
    done

    #don't want to listen?
    if ps -p ${EMULATOR_PID} > /dev/null 2>&1
    then
        #eat this!
        kill -9 ${EMULATOR_PID}
    fi
}

function poweroff_device {
	adb shell reboot -p
}

function list_devices {
    avdmanager list avd
}

function is_device_ready {
    BOOT_COMPLETE="$(adb shell getprop sys.boot_completed 2>&1 | tr -d '\r' | grep 1)"
    if [ "${BOOT_COMPLETE}" = "1" ] && adb shell pm list packages > /dev/null 2>&1 
    then
        return 0
    else
        return 1
    fi
}

function isScreenOn {
	if adb shell dumpsys power | grep 'mScreenOn=true' > /dev/null 2>&1
	then
		return 0
	else
		return 1
	fi
}

function isScreenLocked {
	if adb shell dumpsys window policy | grep 'mShowingLockscreen=true' > /dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

function turn_on_screen {
	adb shell input keyevent 26 &	
	COUNT=10
	while ! isScreenOn && [ $((COUNT--)) -gt 0 ]
	do
		sleep 1
	done

	isScreenOn || echo "Failed to turn screen on" && exit 1 
}

function unlock_device {
	echo "Unlocking device"	
	if ! isScreenOn
	then
		turn_on_screen
	fi

	if isScreenLocked
	then
		adb shell input keyevent 82 &
	fi
	COUNT=10
    while isScreenLocked && [ $((COUNT--)) -gt 0 ]
    do
        sleep 1
    done
	isScreenLocked && echo "Failed to unlock screen" && exit 1
}

function start_device {
    eval cd "${ANDROID_HOME}/emulator"
    ./emulator -port ${PORT} -avd "${AVD_NAME}" ${EMULATOR_OPTS} &
    EMULATOR_PID=$!
    TIMEOUT=30
    while [ $((TIMEOUT--)) -gt 0 ]
    do
        is_device_ready && break
        sleep 1
    done

    if ! is_device_ready
    then
        echo "Error: starting of emulator timed out"
        kill_emulator ${EMULATOR_PID}
        exit 1
    fi

	echo "Device started and ready."

	unlock_device
}

function reboot_device {
	kill_emulator

	start_device	
}

function enable_animations {
	adb shell settings put global window_animation_scale 1.0
	adb shell settings put global transition_animation_scale 1.0
	adb shell settings put global animator_duration_scale 1.0
}

function disable_animations {
	adb shell settings put global window_animation_scale 0.0
	adb shell settings put global transition_animation_scale 0.0
	adb shell settings put global animator_duration_scale 0.0
}

function create_avd {
    avdmanager -v create avd -g google_apis -b x86 -d 'Nexus 5' -n "${AVD_NAME}" -c 100M -k "system-images;${TARGET};google_apis;x86"
}

function remove_avd {
    avdmanager -v delete avd -n "${AVD_NAME}"
}

while getopts "t:n:u:r:cdoepslwx?" opt
do
    case $opt in
        b)
            EMULATOR_OPTS="${EMULATOR_OPTS} -no-window -no-audio"
            START_DEVICE=1
        ;;
        p)
            POWEROFF_DEVICE=1
        ;;
        s)
            START_DEVICE=1
        ;;
        l)
            list_devices
            exit 0
        ;;
		e)
			ENABLE_ANIMS=1
		;;
		d)
			ENABLE_ANIMS=0
		;;
		w)
			EMULATOR_OPTS="${EMULATOR_OPTS} -wipe-data"
		;;
		c)
			CREATE_AVD=1
		;;
		n)
			AVD_NAME=${OPTARG}
		;;
		t)
			TARGET=${OPTARG}
		;;
		u)
			PORT=${OPTARG}
		;;
		r)
			REMOVE_AVD=1
		;;
		x)
			UNLOCK_AVD=1
		;;
        \?)
            usage
            exit 1
        ;;
    esac
done

shift $((OPTIND-1))

EMULATOR_PID=$(ps -o pid,command | grep [$]{AVD_NAME} | tr -s ' ' | cut -d ' ' -f 2)

export ANDROID_SERIAL="emulator-${PORT}"

if [ ${START_DEVICE} -eq 1 ]
then
    start_device
elif [ ${POWEROFF_DEVICE} -eq 1 ]
then
    poweroff_device
elif [ ${CREATE_AVD} -eq 1 ]
then
    create_avd
elif [ ${REMOVE_AVD} -eq 1 ]
then
    remove_avd
fi

if [ ${ENABLE_ANIMS} -eq 1 ]
then
	echo "Enabling animations"
	enable_animations
elif [ ${ENABLE_ANIMS} -eq 0 ]
then
	echo "Disabling animations"	
	disable_animations
	echo "Rebooting device to make changes effective"
	poweroff_device
	start_device
fi

[ ${UNLOCK_AVD} -eq 1 ] && unlock_device

