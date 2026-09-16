#!/bin/bash
# Run from a reviewed release checkout. Credentials stay in Xcode/Keychain.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"
: "${MFL_BACKGROUND_SYNC_URL:?Set the private HTTPS scoring service URL}"
: "${NFL_SCORING_URL:?Set the private HTTPS NFL cache URL}"
archive_path=${MFL_ARCHIVE_PATH:-/tmp/MFLBlitz-TestFlight.xcarchive}
if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  echo 'Commit the reviewed source before creating the distribution archive.' >&2
  exit 1
fi
# Archive a clean tracked snapshot; unrelated synchronized duplicate files must
# never silently enter an Xcode file-system-synchronized source group.
release_source=$(mktemp -d /tmp/mfl-testflight-source.XXXXXX)
git archive HEAD | tar -x -C "$release_source"
git rev-parse HEAD > "$release_source/RELEASE-COMMIT.txt"
xcodebuild archive -project "$release_source/MFLBlitz.xcodeproj" -scheme MFLBlitz \
  -configuration Release -destination 'generic/platform=iOS' -archivePath "$archive_path" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=CP6ZMDE546 \
  MFL_BACKGROUND_SYNC_URL="$MFL_BACKGROUND_SYNC_URL" NFL_SCORING_URL="$NFL_SCORING_URL" \
  "$@"
echo "Archive: $archive_path"
echo "Source revision: $(cat "$release_source/RELEASE-COMMIT.txt")"
