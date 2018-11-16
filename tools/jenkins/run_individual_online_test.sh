#!/usr/bin/env bash

SCRIPT_DIR="$(dirname $0)"
source "${SCRIPT_DIR}"/functions

function usage
{
    echo "Usage: $0 [-d <DEBUG_LEVEL>] <TARGET> <TEST_METHOD>"
}

while getopts "d:" opt
do
  case $opt in
    d)
        DEBUG="${OPTARG}"
    ;;
    \?)
        usage && exit 1
    ;;
  esac
done

shift $((OPTIND - 1))

[ $# -ne 2 ] && usage && exit 1

TARGET="${1}"
TEST_METHOD="${2}"

# Convert target name to <CAPITAL><lowercase> format. E.g. BOT => Bot
TARGET=$(sanitize_target_name "${TARGET}")

APK="$(get_apk ${TARGET})"
[ -e "${APK}" ] || (echo "ERROR: unable to find APK for ${TARGET}" && exit 1)

TEST_APK="$(get_test_apk ${TARGET})"
[ -e ${TEST_APK} ] || (echo "ERROR: unable to find test APK for ${TARGET}" && exit 1)

MIN_SDK=$(apkanalyzer manifest min-sdk ${APK})
MAX_SDK=$(apkanalyzer manifest target-sdk ${APK})
APP_ID=$(apkanalyzer manifest application-id ${APK})

adb uninstall ${APP_ID}
adb uninstall ${APP_ID}.test
adb install ${APK} || exit 1
adb install ${TEST_APK} || exit 1

debug 1 "Test method ${TEST_METHOD}"
debug 1 "App id: ${APP_ID}"

TEST_RESULT_FILE="/tmp/.TEST_RESULT"
run_test "${APP_ID}" "${TEST_METHOD}" > "${TEST_RESULT_FILE}" 2>&1 &

show_progression $! 60
RES=$?
[ ${RES} -eq 2 ] && echo "Time out exceeded!"
[ ${RES} -eq 1 ] && echo "Error: adb command failed."

cat ${TEST_RESULT_FILE}