#!/bin/sh
# Xcode Cloud: assign a unique, increasing CFBundleVersion before xcodebuild.
# Uses CI_BUILD_NUMBER (auto-incremented by Xcode Cloud for this product).
#
# If App Store Connect already has higher build numbers than this workflow
# (e.g. from local archives), add an Environment Variable in the Xcode Cloud
# workflow: CI_BUNDLE_VERSION_OFFSET = <integer>
# Final build = CI_BUILD_NUMBER + CI_BUNDLE_VERSION_OFFSET.
#
# Docs: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "ci_pre_xcodebuild: CI_BUILD_NUMBER unset — skipping (not Xcode Cloud)."
  exit 0
fi

OFFSET="${CI_BUNDLE_VERSION_OFFSET:-0}"
case "$OFFSET" in
  ''|*[!0-9]*)
    echo "ci_pre_xcodebuild: CI_BUNDLE_VERSION_OFFSET must be a non-negative integer (got: ${OFFSET})"
    exit 1
    ;;
esac

NEW_BUILD=$((CI_BUILD_NUMBER + OFFSET))

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
fi

PBXPROJ="${REPO_ROOT}/TheGomsons.xcodeproj/project.pbxproj"
if [ ! -f "$PBXPROJ" ]; then
  echo "ci_pre_xcodebuild: missing project at ${PBXPROJ}"
  exit 1
fi

# Update every CURRENT_PROJECT_VERSION in the project (app + test targets).
# GENERATE_INFOPLIST_FILE uses this for CFBundleVersion.
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

echo "ci_pre_xcodebuild: CURRENT_PROJECT_VERSION → ${NEW_BUILD} (CI_BUILD_NUMBER=${CI_BUILD_NUMBER}, offset=${OFFSET})"
