#!/bin/sh

set -eux

./send_build_notification.py started || :

cd ..
make dependencies
