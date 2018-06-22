#!/bin/bash

[ -z "${ANDROID_HOME}" ] && echo "ERROR: ANDROID_HOME variable not defined" && exit 1

function usage {
    echo "Usage: $0 -l | -[deopsl]... DEVICE_NAME"
    echo
    echo "  -d      run device in daemon mode (default: get status)"
    echo "  -p      poweroff device"
    echo "  -s      start device in foreground (default: get status)"
    echo "  -l      list available virtual devices"
    echo "  -o      disable animations globally on device"
    echo "  -e      enable animations globally on device"
    echo
}

function kill_emulator {
    PID=$1

    if ! ps -p $PID > /dev/null 2>&1
    then
        return 1
    fi

    #we start asking nicely
    kill ${PID}

    COUNT=10
    while ps -p $PID > /dev/null 2>&1 && [ $((COUNT--)) -lt 1 ]
    do
        sleep 0.2
    done

    #don't want to listen?
    if ps -p ${PID} > /dev/null 2>&1
    then
        #eat this!
        kill -9 ${PID}
    fi
}

function poweroff_device {
    adb shell reboot -p
}

function list_devices {
    avdmanager list avd
}

function show_status {
    adb get-state
}

function is_device_ready {
    if adb shell pm list packages > /dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

function start_device {
    eval cd "${ANDROID_HOME}/emulator"
    ./emulator -avd "${DEVICENAME}" ${EMULATOR_OPTS} &
    EMULATOR_PID=$!

    TIMEOUT=100
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
}

function enable_animations {
	adb shell settings put global window_animation_scale 1 
	adb shell settings put global transition_animation_scale 1
	adb shell settings put global animator_duration_scale 1
}

function disable_animations {
	adb shell settings put global window_animation_scale 0
	adb shell settings put global transition_animation_scale 0
	adb shell settings put global animator_duration_scale 0
}

export PATH=/bin/:/usr/bin:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools
EMULATOR_OPTS=""
POWEROFF_DEVICE=0
START_DEVICE=0
ENABLE_ANIMS=-1

while getopts ":doepsl" opt
do
    case $opt in
        d)
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
		o)
			ENABLE_ANIMS=0
		;;
        \?)
            usage
            exit 1
        ;;
    esac
done

shift $((OPTIND-1))

[ $# -ne 1 ] && usage && exit 1

DEVICENAME="$1"

if [ ${START_DEVICE} -eq 1 ]
then
    start_device
elif [ ${POWEROFF_DEVICE} -eq 1 ]
then
    poweroff_device
else
    show_status
fi

[ ${ENABLE_ANIMS} -eq 1 ] && enable_animations
[ ${ENABLE_ANIMS} -eq 0 ] && disable_animations
