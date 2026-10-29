#!/bin/sh
# Registers the Google Sign-In callback URL scheme in the built Info.plist.
#
# google_sign_in on iOS needs the reversed iOS client ID
# (com.googleusercontent.apps.<id>) in CFBundleURLTypes, even when the client
# ID is passed to `GoogleSignIn.initialize` in Dart, as auth_repository.dart
# does. The OSS app ships no compiled-in identity, so the scheme can't live in
# the checked-in Runner/Info.plist: each build gets it from the same
# `--dart-define=GOOGLE_OAUTH_CLIENT_ID=<ios client id>` the Dart code reads.
#
# Why a build phase that edits the processed Info.plist, rather than the
# alternatives:
# - Flutter's docs recommend no way to reach dart-defines from Info.plist.
#   They arrive in Xcode only as DART_DEFINES (comma-separated base64
#   `KEY=VALUE` pairs), which an xcconfig cannot decode.
# - Decoding them into an #included xcconfig from a Run Script phase is the
#   common community pattern, but Xcode reads xcconfigs before any phase runs,
#   so each build would get the previous build's client ID. The scheme
#   pre-action workaround fails silently and isn't visible in the build log.
# - A dedicated build setting (`FLUTTER_XCODE_*` environment variable) makes a
#   builder set the same client ID twice. If the two values disagree, sign-in
#   fails at runtime.
# Doing it here, after Info.plist is processed and before signing, means the
# scheme always matches the client ID compiled into this build, whatever
# drives xcodebuild (`flutter build`, `flutter run`, Fastlane, Xcode).
#
# With no client ID the entry is removed and the build succeeds. Google
# sign-in is then disabled: the Dart code refuses before reaching the plugin.
# The script owns only the URL type it names, so other URL types survive.
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
buddy=/usr/libexec/PlistBuddy
url_name=google-sign-in
suffix=.apps.googleusercontent.com

client_id=""
old_ifs=$IFS
IFS=,
for define in ${DART_DEFINES:-}; do
  decoded=$(printf '%s' "$define" | /usr/bin/base64 --decode 2>/dev/null || true)
  case "$decoded" in
    GOOGLE_OAUTH_CLIENT_ID=*) client_id=${decoded#GOOGLE_OAUTH_CLIENT_ID=} ;;
  esac
done
IFS=$old_ifs

# Drop the entry an earlier build added: incremental builds don't always
# reprocess Info.plist, and the client ID may have changed or gone.
i=0
while "$buddy" -c "Print :CFBundleURLTypes:$i" "$plist" >/dev/null 2>&1; do
  name=$("$buddy" -c "Print :CFBundleURLTypes:$i:CFBundleURLName" "$plist" 2>/dev/null || true)
  if [ "$name" = "$url_name" ]; then
    "$buddy" -c "Delete :CFBundleURLTypes:$i" "$plist"
  else
    i=$((i + 1))
  fi
done
if [ "$i" -eq 0 ]; then
  "$buddy" -c "Delete :CFBundleURLTypes" "$plist" 2>/dev/null || true
fi

if [ -z "$client_id" ]; then
  echo "Google sign-in: no GOOGLE_OAUTH_CLIENT_ID dart-define; no URL scheme registered."
  exit 0
fi

id=${client_id%"$suffix"}
case "$id" in
  "$client_id" | "" | *[!A-Za-z0-9-]*)
    echo "error: GOOGLE_OAUTH_CLIENT_ID must be an iOS OAuth client ID ending in $suffix, got '$client_id'."
    exit 1
    ;;
esac
scheme="com.googleusercontent.apps.$id"

"$buddy" -c "Print :CFBundleURLTypes" "$plist" >/dev/null 2>&1 ||
  "$buddy" -c "Add :CFBundleURLTypes array" "$plist"
"$buddy" \
  -c "Add :CFBundleURLTypes:0 dict" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLName string $url_name" \
  -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Editor" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
  -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $scheme" \
  "$plist"
echo "Google sign-in: registered URL scheme $scheme."
