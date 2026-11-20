#!/usr/bin/env bash
# Runs what a phone can answer by itself, the way docs/dev/ANDROID_VERIFICATION.md asks for it:
# install the debug APK, launch it, and report a crash or a bad package out loud. The checks that
# need a person (a rest timer sounding, a watch pairing, a backup coming back) are printed at the
# end as the list they are.
#
#   scripts/android/verify-device.sh [path/to/app-sideload-debug.apk]
#
# Needs one device, unlocked and authorised (`adb devices` says "device", not "unauthorized").
# Debug build only: it has its own package (io.github.redliner7.androgym.test), so it installs
# next to a release build and touches none of its data.
set -euo pipefail
cd "$(dirname "$0")/../.."

apk=${1:-frontend/android/app/build/outputs/apk/sideload/debug/app-sideload-debug.apk}
if [ ! -f "$apk" ]; then
  echo "no APK at $apk"
  echo "build one first: (cd frontend && npm run build:mobile) && (cd frontend/android && ./gradlew --no-daemon assembleSideloadDebug)"
  exit 2
fi

command -v adb >/dev/null || { echo "adb is not on PATH (Android SDK platform-tools)"; exit 2; }
adb start-server >/dev/null 2>&1 || true

devices=$(adb devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}')
if [ -z "$devices" ]; then
  echo "no authorised device. On the phone: USB debugging on, unlock it, accept the RSA prompt."
  adb devices
  exit 2
fi
if [ "$(printf '%s\n' "$devices" | wc -l)" -gt 1 ]; then
  echo "more than one device attached; set ANDROID_SERIAL to pick one:"; printf '  %s\n' $devices
  exit 2
fi
serial=$devices
echo "device: $serial ($(adb -s "$serial" shell getprop ro.product.model | tr -d '\r'))"

fail=0
say() { printf '%s %s\n' "$1" "$2"; }
ok() { say "  ok  " "$1"; }
bad() { say "  FAIL" "$1"; fail=1; }

# 1. The APK really is the Android build of this fork, before it goes on the phone.
aapt2=$(ls ${ANDROID_HOME:-$HOME/.android-sdk/sdk}/build-tools/*/aapt2 \
  ${ANDROID_HOME:-$HOME/.android-sdk/sdk}/build-tools/*/aapt2.exe 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$aapt2" ]; then
  badging=$("$aapt2" dump badging "$apk")
  pkg=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  ver=$(printf '%s\n' "$badging" | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p")
  label=$(printf '%s\n' "$badging" | sed -n "s/^application-label:'\([^']*\)'.*/\1/p")
  case "$pkg" in
    io.github.redliner7.androgym*) ok "APK package $pkg, version $ver, label $label" ;;
    *) bad "APK package is $pkg, expected io.github.redliner7.androgym (test suffix for debug)" ;;
  esac
  manifest="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
  if printf '%s\n' "$manifest" | grep -q 'AndroGymWidgetProvider'; then
    ok "widget provider is AndroGymWidgetProvider"
  else
    bad "the widget provider under the old name is still in the manifest"
  fi
else
  echo "  (aapt2 not found: skipping the package check)"
fi

# 2. Install over whatever is there.
echo
echo "installing $apk"
if adb -s "$serial" install -r "$apk" >/tmp/adb-install.$$ 2>&1; then
  ok "installed"
else
  cat /tmp/adb-install.$$
  bad "install refused (see the reason above)"
fi
rm -f /tmp/adb-install.$$

# 3. What the phone says it now has.
installed=$(adb -s "$serial" shell dumpsys package io.github.redliner7.androgym.test 2>/dev/null \
  | sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r')
if [ -n "$installed" ]; then ok "phone reports versionName $installed"; else bad "the package is not on the phone"; fi

# 4. Cold start from a stopped process, the way the boot-screen check wants it.
adb -s "$serial" shell am force-stop io.github.redliner7.androgym.test
adb -s "$serial" logcat -c 2>/dev/null || true
if adb -s "$serial" shell monkey -p io.github.redliner7.androgym.test -c android.intent.category.LAUNCHER 1 \
    >/tmp/adb-launch.$$ 2>&1; then
  ok "launcher intent accepted"
else
  bad "the launcher activity did not start"
fi
rm -f /tmp/adb-launch.$$
sleep 12

pid=$(adb -s "$serial" shell pidof io.github.redliner7.androgym.test | tr -d '\r' || true)
if [ -n "$pid" ]; then ok "still running 12 s after launch (pid $pid)"; else bad "the process died during the first 12 s"; fi

crashes=$(adb -s "$serial" logcat -d 2>/dev/null | grep -E 'FATAL EXCEPTION|AndroidRuntime: Process: io.github.redliner7.androgym' || true)
if [ -z "$crashes" ]; then ok "no fatal exception in logcat since launch"; else bad "crash in logcat:"; printf '%s\n' "$crashes"; fi

webview=$(adb -s "$serial" logcat -d 2>/dev/null | grep -cE 'chromium.*(ERR_|net::ERR)' || true)
[ "$webview" = "0" ] && ok "no failed resource loads in the WebView" \
  || echo "  note  $webview failed loads in the WebView console (a missing media file shows up here)"
adb -s "$serial" logcat -d > "./android-logcat-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null || true
echo "  note  full logcat saved to android-logcat-*.txt in this directory"

# 5. What a script cannot answer. Same list as docs/dev/ANDROID_VERIFICATION.md.
cat <<'CHECKLIST'

Still for a person, in this order (docs/dev/ANDROID_VERIFICATION.md):
  - first launch offers local or server, and local reaches Home with no sign-in
  - no tab bar under the navigation bar, no header under the status bar
  - a workout, a routine and a weigh-in save, then survive a force-stop and relaunch
  - a rest timer keeps counting in the notification and sounds at zero
  - Health Connect gets the finished workout, and does not import it back
  - JSON and zip export import back after clearing app data
  - the AndroGym widget renders, and Log set works with the app closed
  - a Wear OS set reaches the phone
  - the gym reminder asks for permission only after it is switched on
  - gym search returns OpenStreetMap places and keeps the pin
  - Settings → About reports no update without an error

CHECKLIST
[ "$fail" = "0" ] && echo "mechanical checks: all passed" || { echo "mechanical checks: see FAIL above"; exit 1; }
