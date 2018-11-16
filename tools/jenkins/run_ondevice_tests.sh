#!/usr/bin/env bash

LOG_FILE="$0.log"
TEST_RESULT_FILE="/tmp/.TEST_RESULT"

# used by adb commands to determine target device
export ANDROID_SERIAL="emulator-5556"

SCRIPT_DIR="$(dirname $0)"
source "${SCRIPT_DIR}"/functions

function load_configuration
{
    CONFS_COUNT=0
    source ./app/src/androidTest/devices_config.rc > /dev/null 2>&1 && ((CONFS_COUNT++))
    source "./app/src/androidTest${TARGET}/devices_config.rc" > /dev/null 2>&1 && ((CONFS_COUNT++))

    [ ${CONFS_COUNT} -eq 0 ] && log "WARNING: No configuration file 'devices_config.rc' found in androidTest dirs."

    if [ -z "${DEFAULT_DEVICE_MODEL}" ]
    then
        DEFAULT_DEVICE_MODEL="Nexus 5"
        DEFAULT_DEVICE_RAM="1536"
        DEFAULT_DEVICE_HEAP="128"
        log "WARNING: DEFAULT_DEVICE_MODEL not set, using ${DEFAULT_DEVICE_MODEL} (RAM: ${DEFAULT_DEVICE_RAM} HEAP: ${DEFAULT_DEVICE_HEAP})"
    fi

    if [ -z "${MIN_DEVICE_MODEL}" ]
    then
        MIN_DEVICE_MODEL=${DEFAULT_DEVICE_MODEL}
        MIN_DEVICE_RAM=${DEFAULT_DEVICE_RAM}
        MIN_DEVICE_HEAP=${DEFAULT_DEVICE_HEAP}
        log "WARNING: MIN_DEVICE_MODEL not set, using ${MIN_DEVICE_MODEL} (RAM: ${MIN_DEVICE_RAM} HEAP: ${MIN_DEVICE_HEAP})"
    fi

    if [ -z "${MAX_DEVICE_MODEL}" ]
    then
        MAX_DEVICE_MODEL=${DEFAULT_DEVICE_MODEL}
        MAX_DEVICE_RAM=${DEFAULT_DEVICE_RAM}
        MAX_DEVICE_HEAP=${DEFAULT_DEVICE_HEAP}
        log "WARNING: MAX_DEVICE_MODEL not set, using ${MAX_DEVICE_MODEL} (RAM: ${MAX_DEVICE_RAM} HEAP: ${MAX_DEVICE_HEAP})"
    fi
}

function is_app_running
{
    if adb shell ps | grep ${PACKAGE} > /dev/null 2>&1
    then
		return 0
	else
		return 1
    fi
}

function wait_for_app_to_start
{
	PACKAGE="${1}"
	TIMEOUT=10
	while [ $((TIMEOUT--)) -gt 0 ]
	do
		if adb shell ps | grep ${PACKAGE} > /dev/null 2>&1
    	then
			return
    	fi
		sleep 1
	done
}

function check_avd
{
    AVD_NAME="${1}"
    AVD_MODEL="${2}"
    AVD_RAM="${3}"
    AVD_HEAP="${4}"
    API_LEVEL="${5}"

    AVD_FILE="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
    [ -r "${AVD_FILE}" ] || return 1
    grep "hw.device.name=${AVD_MODEL}" "${AVD_FILE}" > /dev/null 2>&1 || return 1
    grep "hw.ramSize=${AVD_RAM}" "${AVD_FILE}" > /dev/null 2>&1 || return 1
    grep "vm.heapSize=${AVD_HEAP}" "${AVD_FILE}" > /dev/null 2>&1 || return 1
    grep "image.sysdir.*=.*android-${API_LEVEL}.*" "${AVD_FILE}" > /dev/null 2>&1 || return 1

    return 0
}

function start_emulator
{
    [ -z ${5} ] && ( echo "ERROR: start_emulator requires five arguments" && return )

    AVD_MODEL="${1}"
    AVD_RAM="${2}"
    AVD_HEAP="${3}"
    API_LEVEL="${4}"
    RETRIES="${5}"

    [ ${RETRIES} -lt 0 ] && return

    PORT_NUMBER=$((5556+${API_LEVEL}))
    ANDROID_SERIAL="emulator-${PORT_NUMBER}"
    AVD_NAME="test-${API_LEVEL}"

    if ! sdkmanager "system-images;android-${API_LEVEL};google_apis;x86" > ${LOG_FILE} 2>&1
    then
        log "ERROR: installing android-${API_LEVEL} system image failed. See ${LOG_FILE} for details"
        exit 1
    fi

    if ! check_avd "${AVD_NAME}" "${AVD_MODEL}" "${AVD_RAM}" "${AVD_HEAP}" "${API_LEVEL}"
    then
        log "Creating an emulator for Android API level ${API_LEVEL}"
        ./tools/manage_emulator.sh -r -n "${AVD_NAME}" > /dev/null 2>&1
        ./tools/manage_emulator.sh -c -t "android-${API_LEVEL}" -n "${AVD_NAME}" -o "${AVD_MODEL}" -H "${AVD_HEAP}" -m "${AVD_RAM}" || exit 1
    fi

    log "Starting emulator ${AVD_NAME} running Android API ${API_LEVEL} on port ${PORT_NUMBER}"
    if ! ./tools/manage_emulator.sh -s -w -u ${PORT_NUMBER} -n ${AVD_NAME}
    then
        log "Failed to start emulator, creating a new one"
        ./tools/manage_emulator.sh -r -n ${AVD_NAME}
        start_emulator "${AVD_MODEL}" "${AVD_RAM}" "${AVD_HEAP}" "${API_LEVEL}" "$((RETRIES - 1))"
    fi

    # disable animations. If this fails, power off the emulator and restart it
    if ! ./tools/manage_emulator.sh -d -u ${PORT_NUMBER} -n "${AVD_NAME}"
    then
        log "Disabling animations failed. Killing emulator and starting it again."
        ./tools/manage_emulator.sh -p -n "${AVD_NAME}" && start_emulator "${AVD_MODEL}" "${AVD_RAM}" "${AVD_HEAP}" "${API_LEVEL}" "$((RETRIES - 1))"
    fi

    # unlock device
    ./tools/manage_emulator.sh -x -u ${PORT_NUMBER} -n "${AVD_NAME}" || exit 1
}

function stop_emulator
{
    PORT_NUMBER=$((5556+${API_LEVEL}))
    log "Stopping emulator ${AVD_NAME}"
    ./tools/manage_emulator.sh -p -u ${PORT_NUMBER} -n ${AVD_NAME}
}

function reset_adb
{
    # Reset adb server to prevent stalled daemons from stalling adb commands
    adb kill-server
    adb start-server
}

function is_screenrecord_supported
{
    adb root
    if adb shell 'screenrecord --time-limit 1 /data/data/test.mp4 > /dev/null 2>&1 || echo Screen recording not supported' | grep 'Screen recording not supported'
    then
        return 1
    else
        return 0
    fi
}

function start_screenrecording
{
    AVD_VIDEO_FILE="${1}"

    if adb shell mkdir -p $(dirname ${AVD_VIDEO_FILE}) >> ${LOG_FILE} 2>&1
    then
        adb shell screenrecord ${AVD_VIDEO_FILE} >> ${LOG_FILE} 2>&1 &
    else
        log "ERROR: Unable to start video recorder. Failed to create directory $(dirname ${AVD_VIDEO_FILE}) on ${AVD_NAME}."
        return 1
    fi
}

function stop_screenrecording
{
    adb shell kill -s SIGINT '$(pgrep screenrecord)'
    sleep 1
}

function run_test_method
{
    TEST_METHOD="${1}"

    echo -n "Testing method ${TEST_METHOD}"

    run_test "${APP_ID}" "${TEST_METHOD}" > "${TEST_RESULT_FILE}" 2>&1 &

    show_progression $! 60
    RES=$?
    [ ${RES} -eq 2 ] && echo "Time out exceeded!" && return 1
    [ ${RES} -eq 1 ] && ( debug 1 "Error: adb command failed." && debug 2 "$(cat ${TEST_RESULT_FILE})" )

    # If status code is negative test failed
    TEST_RESULT=$(grep "INSTRUMENTATION_STATUS_CODE: -2" "${TEST_RESULT_FILE}")

    if [ -n "${TEST_RESULT}" ]
    then
        debug 1 "Test failed"
        return 1
    else
        debug 1 "Test succeeded"
        return 0
    fi
}

function download_video_file
{
    VIDEO_DIR="${1}"
    AVD_VIDEO_FILE="${2}"

    if ! adb pull "${AVD_VIDEO_FILE}" "${VIDEO_DIR}" >> ${LOG_FILE} 2>&1
    then
        log "ERROR: failed to get ${AVD_VIDEO_FILE} from ${ANDROID_SERIAL}"
    fi

    if ! adb shell rm -f "${AVD_VIDEO_FILE}" >> ${LOG_FILE} 2>&1
    then
        log "ERROR: failed to remove ${AVD_VIDEO_FILE} from ${ANDROID_SERIAL}"
    fi
}

function rerun_failed_tests
{
    FAILED_TESTS="${1}"

    TEST_REPORT_DIR="app/build/reports/androidTests/connected/flavors/${TARGET}"
    VIDEO_DIR="${TEST_REPORT_DIR}/videos"

    adb install ${APK} > /dev/null 2>&1 || exit 1
    adb install ${TEST_APK} > /dev/null 2>&1 || exit 1

    IFS='
'
    if ! mkdir -p "${VIDEO_DIR}" >> ${LOG_FILE} 2>&1
    then
        log "ERROR: failed to create directory ${VIDEO_DIR}. Video not saved!"
        exit 1
    fi

    TESTS_FAILED=0
    for TEST in ${FAILED_TESTS}
    do
        # Rewrite: nl.appetite.giesecke.banknote.BanknoteDetailActivityTests > selectFeature[test(AVD) - 4.2.2] FAILED
        # into: nl.appetite.giesecke.banknote.BanknoteDetailActivityTests#selectFeature
        TEST_METHOD="$(echo ${TEST} | sed 's/^\(.*\) > \([^[]*\)\[.*$/\1#\2/')"

        # Run once more separately to minimize flaky test results
        run_test_method "${TEST_METHOD}" && continue

        echo "Test failed: ${TEST_METHOD}"
        TESTS_FAILED=$((TESTS_FAILED + 1))

        is_screenrecord_supported || continue

        echo "Rerunning to get a screen recording"
        start_screenrecording "/data/data/${APP_ID}/videos/${TEST_METHOD}.mp4"
        run_test_method "${TEST_METHOD}"
        stop_screenrecording

        download_video_file "${VIDEO_DIR}" "/data/data/${APP_ID}/videos/${TEST_METHOD}.mp4"
    done

    TEST_REPORT_DIR="app/build/reports/androidTests/connected/flavors/${TARGET}"

    if mkdir -p ${TEST_REPORT_DIR}-api-${API_LEVEL} &&
        cp -r ${TEST_REPORT_DIR}/* ${TEST_REPORT_DIR}-api-${API_LEVEL} &&
        [ ${TESTS_FAILED} -gt 0 ]
    then
        echo "See ${TEST_REPORT_DIR}-api-${API_LEVEL} for more details."
    else
        log "Failed to save report files from ${TEST_REPORT_DIR} to ${TEST_REPORT_DIR}-api-${API_LEVEL}"
    fi
}

function android_test
{
    API_LEVEL="${1}"
    APP_ID="${2}"
    TIME_OUT=600 # 10 minutes

    echo "Starting android test for ${1}"

    # Deinstall any previous apks
    ./gradlew uninstall${TARGET}DebugAndroidTest >> ${LOG_FILE} 2>&1 &

    # First use the standard method to run all android tests
    echo -n "Running connected${TARGET}DebugAndroidTest"
    ./gradlew connected${TARGET}DebugAndroidTest > ${TEST_RESULT_FILE} 2>&1 &
    show_progression $! ${TIME_OUT}
    if [ $? -eq 2 ]
    then
       log "ERROR: running connected${TARGET}DebugAndroidTest did not complete within ${TIME_OUT} seconds!"
       return 1
    elif [ $? -eq 0 ]
    then
       echo -e "All tests passed!"
       return
    fi

    # nl.appetite.giesecke.banknote.userstories.ShowSecurityFeatureDetails > showNextSecurityFeatureInfo[test-26(AVD) - 8.0.0] FAILED
    FAILED_TESTS="$(grep '.*>.*FAILED' ${TEST_RESULT_FILE} | uniq)"

    if [ -n "${FAILED_TESTS}" ]
    then
        debug 1 "Following tests failed: \n${FAILED_TESTS}"
        debug 2 "$(cat .TEST_RESULT)"

        echo "Retrying failed tests."
        rerun_failed_tests "${FAILED_TESTS}"
    fi
}

function smoke_test
{
    API_LEVEL="${1}"
    APP_ID="${2}"
    TIME_OUT=600 # 10 minutes

    echo "Starting smoke test for ${1}"

    echo -n "Running smoke test"
    ./gradlew connected${TARGET}DebugAndroidTest \
        -Pandroid.testInstrumentationRunnerArguments.annotation=nl.appetite.testhelpers.SmokeTest \
        > ${LOG_FILE} 2>&1 &
    show_progression $! ${TIME_OUT}
    if [ $? -eq 2 ]
    then
       echo -e "ERROR: running smoke test for ${API_LEVEL} did not complete within ${TIME_OUT} seconds!"
       exit 1
    elif [ $? -eq 0 ]
    then
       echo -e "Smoke test passed!"
       return
    fi

    FAILED_TESTS="$(grep '.*>.*FAILED' ${LOG_FILE})"
    TEST_REPORT_DIR="app/build/reports/androidTests/connected/flavors/${TARGET}"
    echo -e "The following tests failed."
    echo -e "${FAILED_TESTS}"

    if [ -n "${FAILED_TESTS}" ] && is_screenrecord_supported
    then
        echo "Rerunning failing tests to get a screen recording."
        rerun_failed_tests "${FAILED_TESTS}"
    fi
}

DEBUG=0 # debug messages disabled by default (enable using -d commandline argument)
while getopts "d:" opt
do
  case $opt in
    d)
        DEBUG="${OPTARG}"
    ;;
    \?)
        echo "usage: $0 [-d <LEVEL>] <PRODUCT_FLAVOR>" && exit 1
    ;;
  esac
done

shift $((OPTIND -1))
TARGET="$1"

[ -z "${TARGET}" ] && echo "usage: $0 [-d] <PRODUCT_FLAVOR>" && exit 1
TARGET=$(echo ${TARGET:0:1} | tr '[:lower:]' '[:upper:]')$(echo ${TARGET:1} | tr '[:upper:]' '[:lower:]')

load_configuration

APK=$(find ./app/build/outputs/ -iname "app-${TARGET}-debug.apk")
[ -e "${APK}" ] || (echo "ERROR: unable to find APK for ${TARGET}" && exit 1)

TEST_APK=$(find ./app/build/outputs/ -iname "app-${TARGET}-debug-androidTest.apk")
[ -e ${TEST_APK} ] || (echo "ERROR: unable to find test APK for ${TARGET}" && exit 1)

MIN_SDK=$(apkanalyzer manifest min-sdk ${APK})
MAX_SDK=$(apkanalyzer manifest target-sdk ${APK})
APP_ID=$(apkanalyzer manifest application-id ${APK})

reset_adb

#sdkmanager --install "platforms;android-${MIN_SDK}"
#start_emulator "${MIN_DEVICE_MODEL}" "${MIN_DEVICE_RAM}" "${MIN_DEVICE_HEAP}" "${MIN_SDK}" 2
#android_test ${MIN_SDK} ${APP_ID}
#stop_emulator

sdkmanager --install "platforms;android-${MAX_SDK}"
start_emulator "${MAX_DEVICE_MODEL}" "${MAX_DEVICE_RAM}" "${MAX_DEVICE_HEAP}" "${MAX_SDK}" 2
android_test ${MAX_SDK} ${APP_ID}
#stop_emulator

#for API_LEVEL in $(seq $((${MIN_SDK}+1)) $((${MAX_SDK}-1)))
#do
#    [ ${API_LEVEL} -eq 20 ] && continue
#
#    start_emulator "${DEFAULT_DEVICE_MODEL}" "${DEFAULT_DEVICE_RAM}" "${DEFAULT_DEVICE_HEAP}" "${API_LEVEL}" 2
#
#    smoke_test ${API_LEVEL} ${APP_ID}
#
#    stop_emulator
#done
