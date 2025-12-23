#!/usr/bin/env zsh

LOG_DIR="$HOME/Library/Logs/Signal-CI"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

SCHEMA_DIR="$HOME/Library/Signal-iOS-Schema"
rm -rf "$SCHEMA_DIR"
mkdir -p "$SCHEMA_DIR"

echo
echo "Available iOS Simulator runtimes:"
xcrun simctl list runtimes

echo
echo "Available iOS Simulators:"
xcrun simctl list devices

LATEST_IOS_RUNTIME=$(
  xcrun simctl list runtimes -j \
    | jq -r '.runtimes | map(select(.name | startswith("iOS"))) | sort_by(.version) | last | .identifier'
)
echo
echo "Using latest iOS runtime: $LATEST_IOS_RUNTIME"

LATEST_IOS_SIM_ID=$(
  xcrun simctl list devices -j \
    | jq -r --arg runtime "$LATEST_IOS_RUNTIME" '.devices[$runtime] | first | .udid'
)
echo
echo "Using simulator: $LATEST_IOS_SIM_ID"

echo
set -o pipefail \
&& NSUnbufferedIO=YES TEST_RUNNER_SCHEMA_DUMP_PATH="$SCHEMA_DIR/schema.json" xcodebuild \
  -workspace Signal.xcworkspace \
  -scheme Signal \
  -destination "platform=iOS Simulator,id=$LATEST_IOS_SIM_ID" \
  -disableAutomaticPackageResolution \
  -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 300 \
  -default-test-execution-time-allowance 60 \
  -resultBundlePath "$LOG_DIR/TestResult.xcresult" \
  build test \
  2>&1 \
| tee "$LOG_DIR/Signal-CI.log" \
| xcbeautify \
  --renderer github-actions \
  --disable-logging \
| while IFS= read -r line; do
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$line"
done

XCODEBUILD_RESULT_CODE=$?

xcrun \
  xcresulttool \
  get \
  test-results \
  summary \
  --path "$LOG_DIR/TestResult.xcresult" \
  > "$LOG_DIR/TestResultSummary.json"

Scripts/parse-xcresult.py "$LOG_DIR/TestResultSummary.json"

exit $XCODEBUILD_RESULT_CODE
