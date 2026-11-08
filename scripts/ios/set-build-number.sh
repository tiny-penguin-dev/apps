#!/bin/sh
# Xcode "Set build number" run script phase: writes the build number from
# build-number.sh into the target's built Info.plist, so a build made in Xcode
# gets the same number CI gives that commit. Every app and extension target runs it.
NUMBER="$("$(dirname "$0")/build-number.sh" 2>/dev/null)"
if [ -z "$NUMBER" ]; then
  echo "warning: Couldn't read the commit time from git, so the build number stays $CURRENT_PROJECT_VERSION."
  exit 0
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
