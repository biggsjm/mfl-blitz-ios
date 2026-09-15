#!/bin/bash
# Requires an Apple Developer account/profile with Push Notifications enabled.
# Use a separate app entitlement variable so the widget never receives aps-environment.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"
xcodebuild build -project MFLBlitz.xcodeproj -scheme MFLBlitz -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/mfl-background-device \
  DEVELOPMENT_TEAM=CP6ZMDE546 MFL_BACKGROUND_PUSH_FLAG=MFL_BACKGROUND_PUSH \
  MFL_CODE_SIGN_ENTITLEMENTS=MFLBlitz/Support/MFLBlitzPush.entitlements \
  MFL_CODE_SIGN_STYLE=Manual MFL_PROVISIONING_PROFILE_SPECIFIER="MFL Blitz Push Development" \
  MFL_APNS_ENVIRONMENT=development "$@"
