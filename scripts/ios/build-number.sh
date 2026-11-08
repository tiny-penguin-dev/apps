#!/bin/sh
# Prints the build number for the commit that's checked out: its commit time in
# Pacific time, YYYYMMDDHHMM (e.g. 202611072315). CI and local Xcode builds both
# use this, so the same commit always gets the same build number.
# Builds before 8 Nov 2026 used UTC instead (see docs/ios-release.md).
cd "$(dirname "$0")" || exit 1
TZ=America/Los_Angeles exec git show -s --format=%cd --date=format-local:%Y%m%d%H%M HEAD
