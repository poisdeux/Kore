#!/usr/bin/env sh

set -x

function usage {
    echo "Usage: $0 [OPTION]"
    echo
    echo "  -s <FILE>   start recording screen saving to FILE"
    echo "  -c <FILE>   stop recording screen for FILE"
    echo
}

function start_recording {
    if type screenrecord
    then
        screenrecord ${FILENAME} &
        echo $! > "${PIDFILE}"
    else
        exit 2
    fi
}

function stop_recording {
    [ -e "${PIDFILE}" ] || exit 1
    PID=$(cat "${PIDFILE}")
    kill ${PID}
    RETRIES=20
    while [ -e "/proc/${PID}" ] && [ $((RETRIES--)) -gt 0 ]
    do
        sleep 0.1
    done
    if [ -e "/proc/${PID}" ]
    then
        kill -9 ${PID}
    fi
    rm ${PIDFILE}
}

while getopts "c:s:" opt
do
    case $opt in
        s)
            FILENAME="${OPTARG}"
            PIDFILE="$(dirname ${FILENAME})/.$(basename $0)"
            start_recording
            exit 0
        ;;
        c)
            FILENAME="${OPTARG}"
            PIDFILE="$(dirname ${FILENAME})/.$(basename $0)"
            stop_recording
            exit 0
        ;;
    esac
done

usage