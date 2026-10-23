#!/bin/sh
# Re-export the website's parks data for the iOS app (state parks, national parks, tribal & scenic landmarks).
# Run from the repo root after the website's parks files change (src/stateParksData*.ts, src/curatedStateParks.ts,
# src/nationalParksData*.ts, src/tribalAndScenicParksData.ts).
set -e
npx esbuild ios-native/scripts/export-parks.ts --bundle --platform=node --log-level=error --outfile=/tmp/kt-export-parks.cjs
node /tmp/kt-export-parks.cjs ios-native/KosherTravel/Resources/parks.json
rm -f /tmp/kt-export-parks.cjs
