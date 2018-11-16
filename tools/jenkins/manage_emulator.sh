#!/bin/bash
#
#   Copyright 2017 Martijn Brekhof. All rights reserved.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


[ -z "${ANDROID_SDK_ROOT}" ] && echo "ERROR: ANDROID_SDK_ROOT variable not defined" && exit 1

export PATH=/bin/:/usr/bin:${ANDROID_SDK_ROOT}/tools/bin:${ANDROID_SDK_ROOT}/platform-tools
EMULATOR_OPTS="-no-snapshot -gpu host"
POWEROFF_DEVICE=0
START_DEVICE=0
ENABLE_ANIMS=-1
CREATE_AVD=0
REMOVE_AVD=0
UNLOCK_AVD=0
AVD_NAME="test"
AVD_MODEL="Nexus 5"
AVD_RAM="1536"
AVD_HEAP="128"
TARGET="android-27"
PORT=5556
LOG_FILE="${PWD}/${0}.log"

trap cleanup INT

function usage {
    echo "Usage: $0 -l | [-bcdelprswx] [-H <MEBI>] [-m <MEBI>] [-n <NAME>] [-o <MODEL>] [-t <ANDROID_SDK>] [-u <PORT>]"
    echo
    echo "  -b      run device in daemon mode"
    echo "  -c      create new virtual device (avd)"
    echo "  -d      disable animations globally on device"
    echo "  -e      enable animations globally on device"
    echo "  -H      specify device heap (default: ${AVD_HEAP})"
    echo "  -l      list available virtual devices"
    echo "  -m      specify device RAM (default: ${AVD_RAM})"
    echo "  -n      specify device name (default: ${AVD_NAME})"
    echo "  -o      specify device model (default: ${AVD_MODEL})"
    echo "  -p      poweroff device"
    echo "  -r      remove virtual device"
    echo "  -s      start device in foreground"
    echo "  -t      specify target name for new avd (default: ${TARGET})"
    echo "  -u      port number for emulator (default: ${PORT})"
    echo "  -w      wipe data storage from device"
    echo "  -x      unlock device"
    echo
}

function is_process_alive {
    [ -z ${1} ] && echo "Error: get_emulator_pid requires AVD name as argument" && exit 1
    if ps -p ${1} > /dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

function kill_emulator {
    PID=${1}

    # is process actually running?
    ps -p ${PID} > /dev/null 2>&1 || return

    #we start asking nicely
    kill ${PID}

    COUNT=10
    while ps -p ${PID} > /dev/null 2>&1 && [ $((COUNT--)) -gt 0 ]
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

function get_emulator_pid {
    [ -z ${1} ] && echo "Error: get_emulator_pid requires AVD name as argument" && exit 1
    echo $(ps -eo pid,command | grep "qem[u].*"${1} | sed 's/^ *\([0-9][0-9]*\)[^0-9].*/\1/')
}

function poweroff_device {
	adb shell reboot -p &

	TIMEOUT=30
	while [ $((TIMEOUT--)) -gt 0 ] && [ -z $(get_emulator_pid ${AVD_NAME}) ]
	do
	    sleep 1
	done

    EMULATOR_PID=$(get_emulator_pid ${AVD_NAME})
	[ -n ${EMULATOR_PID} ] && kill_emulator ${EMULATOR_PID}
}

function cleanup {
    kill_emulator $(get_emulator_pid ${AVD_NAME})
}

function list_devices {
    avdmanager list avd
}


function wait_for_device {
    WAIT_COUNT=120
    RESULT_FILE=".adb_responding_check"

    rm -f ${RESULT_FILE}

    echo -n "Waiting on device."
    # First test if Android OS claims to be fully booted
    while ( ! grep '^1$' ${RESULT_FILE} > /dev/null 2>&1 ) && [ $((WAIT_COUNT--)) -gt 0 ]
    do
        # We need to run this in the background as sometimes adb hangs when the emulator is unresponsive
        adb shell getprop sys.boot_completed 2>&1 | tr -d '\r' > ${RESULT_FILE} &
        sleep 1
        echo -n "."
    done

    rm -f ${RESULT_FILE} || exit 1

    if [ ${WAIT_COUNT} -lt 1 ]
    then
        echo -e "\nFAILED to connect."
        return 1
    fi

    WAIT_COUNT=30

    # Second check if the package manager has started, so we can upload APK files
    while [ -z ${RESULT_FILE} ] && [ $((WAIT_COUNT--)) -gt 0 ]
    do
        adb shell pm list packages 2> /dev/null > ${RESULT_FILE} &
        sleep 1
        echo -n ","
    done

    rm -f ${RESULT_FILE} || exit 1

    if [ ${WAIT_COUNT} -lt 1 ]
    then
        echo -e "\nFAILED to connect."
        return 1
    else
        echo -e "\nDevice online."
        return 0
    fi
}

function isScreenOn {
    RESULT="$(adb shell dumpsys power)"
	if echo "${RESULT}" | grep -e 'mScreenOn=true' -e 'mWakefulness=Awake' > /dev/null 2>&1
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
    if [ -n "$(get_emulator_pid ${AVD_NAME})" ]
    then
        echo "Emulator ${ANDROID_SERIAL} already running"
        return
    fi

    eval cd "${ANDROID_SDK_ROOT}/emulator"
    ./emulator -port ${PORT} -avd "${AVD_NAME}" ${EMULATOR_OPTS} -debug init > ${LOG_FILE} 2>&1 &
    EMULATOR_PID=$!

    if ! wait_for_device
    then
        echo "ERROR: Starting ${AVD_NAME} timed out. See ${LOG_FILE} for details."
        kill_emulator ${EMULATOR_PID}
        exit 1
    fi
}

function reboot_device {
    REBOOT_COUNT=${1:=0}

    # Needs to run in the background as it sometimes hangs running on the emulator
    adb reboot &
    REBOOT_PID=$!

    sleep 1 # prevent race condition where wait_for_device is checking current state, instead of reboot state

    WAIT_COUNT=30

    # Wait for reboot command to finish
    while is_process_alive ${REBOOT_PID} && [ $((WAIT_COUNT--)) -gt 0 ]
    do
        sleep 1
    done

    if [ ${WAIT_COUNT} -lt 1 ]
    then
        echo "ERROR: Command 'adb reboot' timed out."
        exit 1
    fi

    if ! wait_for_device
    then
        echo "ERROR: rebooting emulator timed out."
        EMULATOR_PID=$(get_emulator_pid ${AVD_NAME})
        if [ ${REBOOT_COUNT} -lt 1  ]
        then
            kill_emulator ${EMULATOR_PID}
            exit 1
        fi

        echo "Trying again..."
        reboot_device $((${REBOOT_COUNT} - 1))
    fi
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

function animations_disabled {
    if adb shell settings get global window_animation_scale | grep 0.0 > /dev/null 2>&1 && \
       adb shell settings get global transition_animation_scale | grep 0.0 > /dev/null 2>&1 && \
       adb shell settings get global animator_duration_scale | grep 0.0 > /dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

function create_avd {
    if ! avdmanager -v create avd -g google_apis -b x86 -d "${AVD_MODEL}" -n "${AVD_NAME}" -c 200M -k "system-images;${TARGET};google_apis;x86" > ${LOG_FILE} 2>&1
    then
        echo "ERROR: failed to create AVD. See ${LOG_FILE} for details"
        exit 1
    fi

    AVD_PATH="$(avdmanager list avd | grep ${AVD_NAME}.avd | grep Path | sed 's/.*Path: //')"

    sed -e '/hw.gpu.enabled.*/d' \
        -e '/hw.gpu.mode.*/d' \
        -e '/hw.camera.back=.*/d' \
        -e '/hw.camera.front=.*/d' \
        -e '/hw.ramSize=.*/d' \
        -e '/vm.heapSize=.*/d' \
        -e '/disk.dataPartition.size=.*/d' \
        -i '' ${AVD_PATH}/config.ini

    echo 'hw.gpu.enabled=yes' >> ${AVD_PATH}/config.ini
    echo 'hw.gpu.mode=auto' >> ${AVD_PATH}/config.ini
    echo "hw.ramSize=${AVD_RAM}" >> ${AVD_PATH}/config.ini
    echo "vm.heapSize=${AVD_HEAP}" >> ${AVD_PATH}/config.ini
    echo 'disk.dataPartition.size=1536m' >> ${AVD_PATH}/config.ini
    echo 'hw.camera.back=virtualscene' >> ${AVD_PATH}/config.ini
    echo 'hw.camera.front=emulated' >> ${AVD_PATH}/config.ini
}

function remove_avd {
    if ! avdmanager -v delete avd -n "${AVD_NAME}" > ${LOG_FILE} 2>&1
    then
        echo "ERROR: failed to remove ${AVD_NAME}. See ${LOG_FILE} for details"
        exit 1
    fi
}

while getopts "H:m:n:o:t:u:bcdelprswx?" opt
do
    case $opt in
        H)
            AVD_HEAP="${OPTARG}"
        ;;
        m)
            AVD_RAM="${OPTARG}"
        ;;
        n)
            AVD_NAME="${OPTARG}"
        ;;
        o)
            AVD_MODEL="${OPTARG}"
        ;;
        t)
            TARGET=${OPTARG}
        ;;
        u)
            PORT=${OPTARG}
        ;;
        b)
            EMULATOR_OPTS="${EMULATOR_OPTS} -no-window -no-audio"
            START_DEVICE=1
        ;;
        c)
            CREATE_AVD=1
        ;;
        d)
            ENABLE_ANIMS=0
        ;;
        e)
            ENABLE_ANIMS=1
        ;;
        l)
            list_devices
            exit 0
        ;;
        p)
            POWEROFF_DEVICE=1
        ;;
        r)
            REMOVE_AVD=1
        ;;
        s)
            START_DEVICE=1
        ;;
        w)
            EMULATOR_OPTS="${EMULATOR_OPTS} -wipe-data"
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

export ANDROID_SERIAL="emulator-${PORT}"

if [ ${START_DEVICE} -eq 1 ]
then
    start_device
elif [ ${POWEROFF_DEVICE} -eq 1 ]
then
    kill_emulator $(get_emulator_pid ${AVD_NAME})
elif [ ${CREATE_AVD} -eq 1 ]
then
    create_avd
elif [ ${REMOVE_AVD} -eq 1 ]
then
    remove_avd
fi

if [ ${ENABLE_ANIMS} -eq 1 ]
then
    if ! wait_for_device
    then
        echo "ERROR: Device $ANDROID_SERIAL not ready."
        exit 1
    fi

	echo "Enabling animations"
	enable_animations
elif [ ${ENABLE_ANIMS} -eq 0 ]
then
    if ! wait_for_device
    then
        echo "ERROR: Device $ANDROID_SERIAL not ready."
        exit 1
    fi

    if ! animations_disabled
    then
	    echo "Disabling animations"
	    disable_animations

	    SDK_VERSION=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
	    if [ ${SDK_VERSION} -lt 24 ]
	    then
	        echo "Rebooting device to make changes effective"
            reboot_device 2 || exit 1
        fi
    fi
fi

[ ${UNLOCK_AVD} -eq 1 ] && unlock_device

exit 0
