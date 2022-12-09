#!/bin/sh

set -e

# PROJECT_DIR will be set when run from xcode, else we infer it
if [ "${PROJECT_DIR}" = "" ]; then
    PROJECT_DIR=`git rev-parse --show-toplevel`
    echo "inferred ${PROJECT_DIR}"
fi

# Capture project hashes that we want to add to the Info.plist
cd $PROJECT_DIR/ThirdParty/WebRTC/
_git_commit_webrtc=`git log --pretty=oneline --decorate=no | head -1`
cd $PROJECT_DIR
_git_commit_signal=`git log --pretty=oneline --decorate=no | head -1`

# Remove existing .plist entry, if any.
/usr/libexec/PlistBuddy -c "Delete BuildDetails" Signal/Signal-Info.plist || true
# Add new .plist entry.
/usr/libexec/PlistBuddy -c "add BuildDetails dict" Signal/Signal-Info.plist

/usr/libexec/PlistBuddy -c "add :BuildDetails:WebRTCCommit string '$_git_commit_webrtc'" Signal/Signal-Info.plist

echo "CONFIGURATION: ${CONFIGURATION}"
if [ "${CONFIGURATION}" = "App Store Release" ]; then
    /usr/libexec/PlistBuddy -c "add :BuildDetails:XCodeVersion string '${XCODE_VERSION_MAJOR}.${XCODE_VERSION_MINOR}'" Signal/Signal-Info.plist
    /usr/libexec/PlistBuddy -c "add :BuildDetails:SignalCommit string '$_git_commit_signal'" Signal/Signal-Info.plist

    # Use UTC
    _build_datetime=`date -u`
    /usr/libexec/PlistBuddy -c "add :BuildDetails:DateTime string '$_build_datetime'" Signal/Signal-Info.plist

    _build_timestamp=`date +%s`
    /usr/libexec/PlistBuddy -c "add :BuildDetails:Timestamp integer $_build_timestamp" Signal/Signal-Info.plist
fi
