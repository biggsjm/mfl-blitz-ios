#!/bin/bash
# Use an explicit runtime supported by CI's pinned Xcode, not OS:latest.
set -euo pipefail
simulator_id=$(xcrun simctl create 'MFL Blitz CI' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-18-5)
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
printf 'MFL_TEST_DESTINATION=platform=iOS Simulator,id=%s\n' "$simulator_id" >> "$GITHUB_ENV"
