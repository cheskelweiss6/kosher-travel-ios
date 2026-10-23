#!/bin/sh
# Re-export what the website's United States / state / Caribbean / country pages show, for the iOS app
# (Features/StatePage/statepages.json). Run from the website repo root (ios-native/ next to src/) after data changes in src/.
set -e
node ios-native/scripts/export-statepages-extract.mjs src/App.tsx ios-native/scripts/export-statepages.gen.ts
npx esbuild ios-native/scripts/export-statepages.ts --bundle --platform=node --log-level=error \
  --loader:.jpg=empty --loader:.png=empty --loader:.webp=empty --define:import.meta.env={} --outfile=/tmp/kt-export-statepages.cjs
node /tmp/kt-export-statepages.cjs ios-native/KosherTravel/Features/StatePage/statepages.json
rm -f ios-native/scripts/export-statepages.gen.ts /tmp/kt-export-statepages.cjs
