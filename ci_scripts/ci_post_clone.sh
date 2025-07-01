#!/bin/sh

set -eux

./send_build_notification.py started || :

cd ..

if [ "${CI_WORKFLOW-}" = "Nightly (Xcode 26)" ]; then
    : "Skipping version check for Xcode 26"
    mkdir TestFlight
    echo "Xcode 26 build" > TestFlight/WhatToTest.en-US.txt
else
    Scripts/check_xcode_version.py
fi

make dependencies
