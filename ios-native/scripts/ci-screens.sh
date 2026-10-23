#!/bin/bash
# Boots iPhone SE (3rd gen), iPhone 16, iPhone 16 Pro Max (+ an iPad) simulators, installs the app,
# opens each screen through the -ktRoute launch argument and saves screenshots.
#   usage: ci-screens.sh <path/to/KosherTravel.app> <out-dir>
set -uo pipefail
APP="$1"; OUT="$2"
BUNDLE=com.yourkoshertravel.app
mkdir -p "$OUT/png" "$OUT/jpg" "$OUT/logs"
OUT="$(cd "$OUT" && pwd)"   # simctl opens --stdout paths inside the simulator: they must be absolute

ROUTES=("1-explore:home" "2-united-states:usa" "3-colorado:state:colorado" "4-new-york:state:new-york" "5-denver:area:us:denver" "6-caribbean:caribbean" "7-stories:tab:stories")
# feature branches add their own screens: one "<shot-name>:<route>" per line in ios-native/scripts/routes/*.txt
for f in ios-native/scripts/routes/*.txt; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do [ -n "$line" ] && ROUTES+=("$line"); done < "$f"
done
if [ -n "${KT_ONLY_EXTRA_ROUTES:-}" ] && ls ios-native/scripts/routes/*.txt > /dev/null 2>&1; then
  ROUTES=("1-explore:home")
  for f in ios-native/scripts/routes/*.txt; do while IFS= read -r line; do [ -n "$line" ] && ROUTES+=("$line"); done < "$f"; done
fi

xcrun simctl list runtimes -j > /tmp/runtimes.json
xcrun simctl list devicetypes -j > /tmp/devicetypes.json

# name|runtime-id|devicetype-id for each wanted device (newest runtime that supports it)
python3 - > /tmp/devices.txt <<'PY'
import json, re
rt = [r for r in json.load(open('/tmp/runtimes.json'))['runtimes'] if r.get('isAvailable') and r.get('name','').startswith('iOS')]
def ver(r):
    return tuple(int(x) for x in re.findall(r'\d+', r.get('version','0')))
rt.sort(key=ver, reverse=True)
types = json.load(open('/tmp/devicetypes.json'))['devicetypes']
by_name = {t['name']: t['identifier'] for t in types}
def supported(r, tid):
    s = r.get('supportedDeviceTypes')
    return True if s is None else any(x.get('identifier') == tid for x in s)
wants = [
  ('iphone-se', ['iPhone SE (3rd generation)', 'iPhone SE (2nd generation)', 'iPhone 16e']),
  ('iphone-16', ['iPhone 16', 'iPhone 17', 'iPhone 15']),
  ('iphone-16-pro-max', ['iPhone 16 Pro Max', 'iPhone 17 Pro Max', 'iPhone 15 Pro Max']),
  ('ipad', ['iPad (A16)', 'iPad Air 11-inch (M3)', 'iPad (10th generation)', 'iPad Air 11-inch (M2)', 'iPad Pro 11-inch (M4)']),
]
import os
only = [x.strip() for x in os.environ.get('KT_DEVICES', '').split(',') if x.strip()]
if only: wants = [w for w in wants if w[0] in only]
for slug, names in wants:
    done = False
    for n in names:
        tid = by_name.get(n)
        if not tid: continue
        for r in rt:
            if supported(r, tid):
                print(f"{slug}|{n}|{r['identifier']}|{tid}|{r['name']}"); done = True; break
        if done: break
    if not done:
        print(f"{slug}|MISSING|||")
PY
cat /tmp/devices.txt | tee "$OUT/logs/devices.txt"

while IFS='|' read -r SLUG NAME RUNTIME TYPE RTNAME; do
  if [ "$NAME" = "MISSING" ]; then echo "skip $SLUG (no simulator)"; continue; fi
  echo "=== $SLUG: $NAME on $RTNAME"
  UDID=$(xcrun simctl create "kt-$SLUG" "$TYPE" "$RUNTIME")
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b > /dev/null
  xcrun simctl ui "$UDID" appearance light || true
  xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$UDID" "$APP"
  FIRST=1
  for R in "${ROUTES[@]}"; do
    SHOT="${R%%:*}"; ROUTE="${R#*:}"
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
    if ! xcrun simctl launch --stdout="$OUT/logs/$SLUG-$SHOT.out.txt" --stderr="$OUT/logs/$SLUG-$SHOT.err.txt" \
        "$UDID" "$BUNDLE" -ktRoute "$ROUTE" >> "$OUT/logs/launch.txt" 2>&1; then
      echo "launch failed: $SLUG $SHOT" | tee -a "$OUT/logs/launch.txt"
      xcrun simctl launch "$UDID" "$BUNDLE" -ktRoute "$ROUTE" >> "$OUT/logs/launch.txt" 2>&1 || true
    fi
    if [ $FIRST = 1 ]; then
      sleep 8
      { echo "--- $SLUG after 8 s:"; xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i yourkoshertravel || echo "app process NOT running"; } >> "$OUT/logs/launch.txt"
      sleep 8; FIRST=0
      xcrun simctl spawn "$UDID" log show --last 2m --style compact --predicate 'process == "KosherTravel"' > "$OUT/logs/$SLUG-unified-log.txt" 2>&1 || true
    else sleep 9; fi
    xcrun simctl io "$UDID" screenshot "$OUT/png/$SLUG-$SHOT.png" > /dev/null 2>&1
    sips -s format jpeg -s formatOptions 72 "$OUT/png/$SLUG-$SHOT.png" --out "$OUT/jpg/$SLUG-$SHOT.jpg" > /dev/null
    echo "  $SLUG-$SHOT"
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" || true
  # crash reports, if the app crashed
  grep -l "KosherTravel" ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -3 | while read -r f; do cp "$f" "$OUT/logs/crash-$SLUG-$(basename "$f").txt"; done || true
  xcrun simctl shutdown "$UDID" || true
  xcrun simctl delete "$UDID" || true
  if ls "$OUT"/logs/crash-"$SLUG"-* > /dev/null 2>&1; then
    echo "the app crashed on $SLUG; skipping the other devices" | tee -a "$OUT/logs/launch.txt"
    break
  fi
done < /tmp/devices.txt
grep -h "\[KT\]" "$OUT"/logs/*.txt | sort | uniq -c > "$OUT/logs/feed-summary.txt" || true
ls -la "$OUT/logs" > "$OUT/logs/listing.txt"
cat "$OUT/logs/feed-summary.txt"
ls -la "$OUT/jpg"
