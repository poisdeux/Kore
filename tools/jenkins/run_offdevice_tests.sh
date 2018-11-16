#!/usr/bin/env bash
TARGET="${1}"
LOGFILE="${0}.log"

[ -z "${TARGET}" ] && echo "usage: $0 <PRODUCT_FLAVOR>" && exit 1

#Make sure target is written as lowercase starting with a capital
TARGET=$(echo ${TARGET:0:1} | tr '[:lower:]' '[:upper:]')$(echo ${TARGET:1} | tr '[:upper:]' '[:lower:]')

function testFailed
{
    echo -e "\e[31m\e[1mFAILED\e[0m, see ${LOGFILE} for details"
    exit 1
}

echo "Running local tests. See ${LOGFILE} for details."
echo

# Clear log file
> ${LOGFILE}

# Build
echo "Testing building ${TARGET}" > ${LOGFILE}
echo -n "Testing building ${TARGET} "
./gradlew assemble${TARGET} >> ${LOGFILE} 2>&1 || testFailed
echo -e "\e[32m\e[1mOK\e[0m"

# Run lint checks
echo >> ${LOGFILE}
echo "Performing static code analysis on ${TARGET}" >> ${LOGFILE}
echo -n "Performing static code analysis on ${TARGET} "
./gradlew lint${TARGET}Debug >> ${LOGFILE} 2>&1 || testFailed
echo -e "\e[32m\e[1mOK\e[0m"

# Run unit tests
echo >> ${LOGFILE}
echo "Executing unit tests for ${TARGET}" >> ${LOGFILE}
echo -n "Executing unit tests for ${TARGET} "
./gradlew test${TARGET}DebugUnitTest --tests 'nl.appetite.giesecke.banknote.unittests.*' >> ${LOGFILE} 2>&1 || testFailed
echo -e " \e[32m\e[1mOK\e[0m"

# Run off device Android tests (Robolectric)
echo >> ${LOGFILE}
echo "Executing off-device Android integration tests for ${TARGET}" >> ${LOGFILE}
echo -n "Executing off-device Android integration tests for ${TARGET} "
./gradlew test${TARGET}DebugUnitTest --tests 'nl.appetite.giesecke.banknote.robolectric.*' >> ${LOGFILE} 2>&1 || testFailed
echo -e " \e[32m\e[1mOK\e[0m"

