#!/usr/bin/env sh
git fetch
git merge upstream/textSecure
git checkout upstream/textSecure Pods
git checkout upstream/textSecure Podfile.lock
