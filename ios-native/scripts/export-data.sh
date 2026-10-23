#!/bin/sh
# Re-export the built-in travel data for the iOS app. Run from the repo root after data changes in src/.
set -e
npx esbuild ios-native/scripts/export-data.ts --bundle --platform=node --log-level=error \
  --loader:.jpg=empty --loader:.png=empty --loader:.webp=empty --outfile=/tmp/kt-export-data.cjs
node /tmp/kt-export-data.cjs ios-native/KosherTravel/Resources/explore.json
