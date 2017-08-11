#!/bin/bash
[ -z "${ANDROID_HOME}" ] && echo "ERROR: ANDROID_HOME variable not defined" && exit 1

function usage {
    echo "Usage: $0 -c <TEST_CLASS_DIR>"
    echo
    echo "  -c <DIR>	directory that holds the test classes"     
    echo
}

export PATH=/bin/:/usr/bin:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools
TESTCLASSPATH=""

while getopts "c:" opt
do
    case $opt in
        c)
		TESTCLASSPATH="${OPTARG}"
        ;;
        \?)
            usage
            exit 1
        ;;
    esac
done

[ $# -eq 0 ] && usage && exit 1

for CLASS in $(find ${TESTCLASSPATH} -name '*.java' | sed -e 's@app/src/androidTest/java/\(.*\)\.java@\1@' -e 's@//*@.@g')
do
    # grep -e '@Test' -e 'public\s*.*(.*)' app/src/androidTest/java/org/xbmc/kore/tests/ui/addons/AddonsActivityTests.java | perl -p0e 's/\@Test.*?public\s+\w+\s+(\w+).*?\n/$1\n/gs'
    # for METHOD in ${CLASS}
    # do
        echo adb shell screenrecord /sdcard/${CLASS}.${METHOD}
        #start recording video named after ${CLASS}
        #adb shell am instrument --no-window-animation -w -e debug false -e class "${CLASS}#${METHOD}" org.xbmc.kore.instrumentationtest.test/android.support.test.runner.AndroidJUnitRunner
        #check if test succeeded, if so remove video  
    # done
done

#adb push /Users/martijn/Projects/Kore/app/build/outputs/apk/app-instrumentationTest-debug.apk /data/local/tmp/org.xbmc.kore.instrumentationtest
#$ adb shell pm install -r "/data/local/tmp/org.xbmc.kore.instrumentationtest"
#Success

#$ adb push /Users/martijn/Projects/Kore/app/build/outputs/apk/app-instrumentationTest-debug-androidTest.apk /data/local/tmp/org.xbmc.kore.instrumentationtest.test
#$ adb shell pm install -r "/data/local/tmp/org.xbmc.kore.instrumentationtest.test"
#Success

#Running tests

#$ adb shell am instrument -w -r   -e debug false -e class org.xbmc.kore.tests.ui.addons.AddonsActivityTests org.xbmc.kore.instrumentationtest.test/android.support.test.runner.AndroidJUnitRunner
#Client not ready yet..
#Started running tests
