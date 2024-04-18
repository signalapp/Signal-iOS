#!/bin/sh

set -eux

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" = 0 ]; then
    ./send_build_notification.py finished || :
else
    ./send_build_notification.py failed || :
fi
