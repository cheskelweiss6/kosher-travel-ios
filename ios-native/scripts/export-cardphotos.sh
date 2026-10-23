#!/bin/sh
# Re-export the city listing cards' photo galleries (the website's PlacePhotosGallery rules) for the iOS app.
# Run from the website repo root (src/ beside ios-native/), after export-data.sh: sh ios-native/scripts/export-cardphotos.sh
set -e
npx esbuild ios-native/scripts/export-cardphotos.ts --bundle --platform=node --log-level=error \
  --loader:.jpg=empty --loader:.png=empty --loader:.webp=empty --outfile=/tmp/kt-export-cardphotos.cjs
node /tmp/kt-export-cardphotos.cjs ios-native/KosherTravel/Resources/explore.json ios-native/KosherTravel/Features/Explore/CityCardPhotoData.swift
