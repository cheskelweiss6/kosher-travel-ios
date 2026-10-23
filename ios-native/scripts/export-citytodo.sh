#!/bin/sh
# Re-export what the website's city "Things to Do" page shows, for the iOS app (Resources/citytodo.json):
# the Top Attractions list (getEnrichedAttractions = CURATED_ATTRACTIONS + NEW_THINGS_TO_DO, src/attractionsDatabase.ts)
# and the "Essential Travel & Logistics Advisories" tips (destination.travelTips), precomputed per city key the app
# uses (us:<id>, dest:<id>), so the app has no matcher to keep in step. Run from the website repo root
# (ios-native/ next to src/) after src/attractionsDatabase.ts, src/newThingsToDo.ts or the destination data change.
# Reuses export-statepages-extract.mjs to copy the website's own convertUSCityToDestination / deduplicateDestinations.
set -e
node ios-native/scripts/export-statepages-extract.mjs src/App.tsx ios-native/scripts/export-citytodo.gen.ts
npx esbuild ios-native/scripts/export-citytodo.ts --bundle --platform=node --log-level=error \
  --loader:.jpg=empty --loader:.png=empty --loader:.webp=empty --define:import.meta.env={} --outfile=/tmp/kt-export-citytodo.cjs
node /tmp/kt-export-citytodo.cjs ios-native/KosherTravel/Resources/citytodo.json "$@"
rm -f ios-native/scripts/export-citytodo.gen.ts /tmp/kt-export-citytodo.cjs
