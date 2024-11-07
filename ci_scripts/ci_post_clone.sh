#!/bin/sh

set -eux

./send_build_notification.py started || :

cd ..
Scripts/check_xcode_version.py
make dependencies
