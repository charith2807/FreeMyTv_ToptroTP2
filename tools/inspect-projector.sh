#!/usr/bin/env bash
# Reads a projector (or TV) over adb and suggests the projector settings for config.properties. Changes nothing.
#
#   tools/inspect-projector.sh 192.168.1.150
#
# Prints the device, its stock home screen (the usual projector_app), the vendor apps grouped by what their names
# suggest, and a starting config. Names are only hints: check an app before adding it to debloat_apps
# (adb shell dumpsys package <name>), and when unsure, protect it.
set -euo pipefail

IP="${1:-}"
[ -n "$IP" ] || { sed -n '2,8p' "$0"; exit 1; }
[[ "$IP" == *:* ]] || IP="$IP:5555"
adb connect "$IP" >/dev/null
export ANDROID_SERIAL="$IP"
adb get-state >/dev/null 2>&1 || { echo "Can't reach $IP: turn on USB debugging (or network debugging) and accept the prompt." >&2; exit 1; }
sh() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

echo "== Device"
echo "model:   $(sh getprop ro.product.manufacturer) $(sh getprop ro.product.model) ($(sh getprop ro.board.platform))"
echo "android: $(sh getprop ro.build.version.release) (SDK $(sh getprop ro.build.version.sdk)), ABIs: $(sh getprop ro.product.cpu.abilist)"
echo "memory:  $(sh cat /proc/meminfo | awk '/MemTotal/{printf "%d MB", $2/1024}'), screen: $(sh wm size | awk '{print $NF}' | tail -1)"
[ "$(sh getprop ro.build.version.sdk)" -ge 28 ] || echo "!! Free My TV needs Android 9 or newer."

# The vendor's home screen, even when Free My TV is the default now (Settings' FallbackHome is only for boot).
HOME_ACT="$(sh cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
  | grep -E '^ *[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+$' | sed 's/^ *//' | grep -Ev '^(io\.freemytv/|com\.android\.settings/)' | head -1 || true)"
echo
echo "== Stock home screen (usually where keystone and focus are): ${HOME_ACT:-not found}"
echo "== Screensaver: $(sh settings get secure screensaver_components)"

# System and Google packages that are never the vendor's own.
COMMON='^(android|com\.android\.|com\.google\.|com\.qualcomm\.|org\.chromium|io\.freemytv)'
VENDOR="$(sh pm list packages -s | sed 's/^package://' | grep -Ev "$COMMON" | sort)"
THIRD="$(sh pm list packages -3 | sed 's/^package://' | grep -Ev "$COMMON" | sort)"

# Bloat can be preinstalled or user-installed (ad SDKs often are); controls are always preinstalled.
DEBLOAT="$(grep -Ei 'screensaver|ads?([._]|$)|advert|promo|upload|report|statistic|analytic|telemetry|track|demo|retail|test|factory|manual|acr' \
  <<<"$VENDOR"$'\n'"$THIRD" | grep -v '^$' | sort -u || true)"
PROTECT="$(grep -Ei 'keystone|focus|trapez|correct|projector|imaging|picture|display|setting|setup|provision|wizard|[._]ota|update|upgrade|remote|bluetooth|pair|tvinput|source|hdmi|launcher|home|luminaos|systemui|input|audio|dolby' \
  <<<"$VENDOR" | grep -Fxv -f <(printf '%s\n' "$DEBLOAT" | grep -v '^$' || echo '-') | sort -u || true)"

echo
echo "== Probably keep (controls, setup, updates, remote): add to protect_apps"
[ -n "$PROTECT" ] && sed 's/^/   /' <<<"$PROTECT" || echo "   (none matched)"
echo
echo "== Possible bloat (ads, telemetry, demos, test apps): check each before adding to debloat_apps"
[ -n "$DEBLOAT" ] && sed 's/^/   /' <<<"$DEBLOAT" || echo "   (none matched)"
echo
echo "== Other preinstalled vendor apps (unclassified: leave them alone unless you know what they do)"
comm -23 <(printf '%s\n' "$VENDOR" | grep -v '^$' | sort -u) <(printf '%s\n' "$PROTECT" "$DEBLOAT" | grep -v '^$' | sort -u) | sed 's/^/   /'
echo "   (the stock screensaver, if listed above, is replaced automatically: no need to add it anywhere)"

join() { grep -v '^$' | paste -sd, - ; }
echo
echo "== Suggested config.properties lines (review them first)"
echo "projector_app=${HOME_ACT:-none}"
echo "protect_apps=$(printf '%s\n' "$PROTECT" | grep -Fxv "${HOME_ACT%%/*}" | join)"
echo "debloat_apps="
echo "#   candidates: $(printf '%s\n' "$DEBLOAT" | join)"
