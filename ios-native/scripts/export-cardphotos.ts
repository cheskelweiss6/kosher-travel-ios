// Exports the website's listing-card photo galleries (src/components/PlacePhotosGallery.tsx) for the native city cards.
// Only the cards where the website's gallery differs from the app's own simple rule (the place's photos, else the
// Chabad / shul / grocery default, else the navy no-photo tile) are written, so the file stays tiny.
// Run from the website repo root (src/ beside ios-native/):  sh ios-native/scripts/export-cardphotos.sh
import { loadAppData, getCuratedAttractionPhoto } from '../../src/appData';
import { resolveLocationPhotos } from '../../src/locationPhotos';
import { isValidImageUrl, getHotelFallbackPhoto } from '../../src/cityHeroPhotos';
import { NO_PHOTO_PLACEHOLDER } from '../../src/photoPlaceholder';
import { categoryDefaultPhoto, isPlaceholderPhoto, CATEGORY_DEFAULT_PHOTOS } from '../../src/categoryDefaults';
import * as fs from 'fs';

const SITE = 'https://www.yourkoshertravel.com';

// PlacePhotosGallery's resolution, line for line (contributed photos and the park-photo lookup are not card data).
function webGallery(name: string, city: string, category: string, fallbackPhoto: string | undefined, providedPhotos: string[] | undefined): string[] {
  const verifiedFallbackPhoto = (fallbackPhoto && isValidImageUrl(fallbackPhoto)) ? fallbackPhoto : null;
  const dbCuratedPhoto = getCuratedAttractionPhoto(name, city);
  const curatedAttractionPhoto = verifiedFallbackPhoto || dbCuratedPhoto;
  const notLegacySvgPlaceholder = (p: string) => !(p.startsWith('data:image/svg') && p !== NO_PHOTO_PLACEHOLDER);
  const rawProvided = (providedPhotos || []).filter(isValidImageUrl).filter(notLegacySvgPlaceholder);
  const rawDynamic: string[] = [];
  const normCategory = (category || '').toLowerCase();
  const normName = (name || '').toLowerCase();
  const isChabad = normCategory.includes('chabad') || normName.includes('chabad');
  const isHotelOrRestaurantCategory = normCategory.includes('hotel') || normCategory.includes('lodging') || normCategory.includes('restaurant');
  const categoryDefault: string | null = categoryDefaultPhoto(category)
    || (isChabad && !isHotelOrRestaurantCategory ? CATEGORY_DEFAULT_PHOTOS.chabad : null);
  let basePhotos: string[] = [];
  if (isChabad) {
    if (rawProvided.length > 0) basePhotos = rawProvided;
    else if (curatedAttractionPhoto && isValidImageUrl(curatedAttractionPhoto)) basePhotos = [curatedAttractionPhoto];
    else basePhotos = [categoryDefault || NO_PHOTO_PLACEHOLDER];
  } else if (curatedAttractionPhoto) {
    const resolvedLocPhotos = resolveLocationPhotos(name, city, category).filter(isValidImageUrl);
    const hasAuthenticNonUnsplash = [curatedAttractionPhoto, ...rawProvided, ...rawDynamic, ...(verifiedFallbackPhoto ? [verifiedFallbackPhoto] : [])].some(p => !p.includes('images.unsplash.com'));
    const otherCandidates = [...rawProvided, ...rawDynamic, ...(verifiedFallbackPhoto ? [verifiedFallbackPhoto] : []), ...resolvedLocPhotos]
      .filter(p => !hasAuthenticNonUnsplash || !p.includes('images.unsplash.com'));
    const uniqueOthers = otherCandidates.filter(p => p !== curatedAttractionPhoto);
    basePhotos = [curatedAttractionPhoto, ...uniqueOthers];
  } else if (rawProvided.length > 0) basePhotos = rawProvided;
  else if (rawDynamic.length > 0) basePhotos = rawDynamic;
  else if (verifiedFallbackPhoto) basePhotos = [verifiedFallbackPhoto, ...resolveLocationPhotos(name, city, category).filter(isValidImageUrl)];
  else {
    const locPhotos = resolveLocationPhotos(name, city, category).filter(isValidImageUrl);
    basePhotos = locPhotos.length > 0 ? locPhotos : [getHotelFallbackPhoto(name, city)];
  }
  basePhotos = basePhotos.filter(notLegacySvgPlaceholder);
  if (basePhotos.length === 0) basePhotos = [categoryDefault || NO_PHOTO_PLACEHOLDER];
  if (categoryDefault) {
    const realPhotos = basePhotos.filter((p) => !isPlaceholderPhoto(p));
    basePhotos = realPhotos.length > 0 ? realPhotos : [categoryDefault];
  }
  // As the app stores it: absolute https URLs; "" is the navy no-photo tile.
  return basePhotos.map((p) => (isPlaceholderPhoto(p) ? '' : p.startsWith('/') ? SITE + p : p));
}

// The app's own rule (CityCardGallery.swift `CityCardPhotos.simple`), kept identical.
function appGallery(name: string, category: string, photos: string[]): string[] {
  const valid = (p: string) => p.trim().length >= 12 && /^https?:\/\//.test(p.trim());
  const own: string[] = [];
  for (const p of photos) if (valid(p) && !own.includes(p)) own.push(p);
  if (own.length) return own;
  const n = name.toLowerCase(), c = category.toLowerCase();
  const cd = categoryDefaultPhoto(category) || (n.includes('chabad') && !/hotel|lodging|restaurant/.test(c) ? CATEGORY_DEFAULT_PHOTOS.chabad : null);
  return [cd ? SITE + cd : ''];
}

const SECTIONS: [string, string][] = [['restaurants', 'restaurant'], ['groceries', 'grocery'], ['chabad', 'chabad'], ['shuls', 'synagogue'], ['hotels', 'hotel']];

async function main() {
  await loadAppData();
  const [input, output] = process.argv.slice(2); // explore.json in, the Swift data file out
  const data = JSON.parse(fs.readFileSync(input, 'utf8'));
  const out: Record<string, string[]> = {};
  let cards = 0;
  for (const d of [...(data.cities || []), ...(data.destinations || [])]) {
    const city = String(d.name || '');
    for (const [field, cat] of SECTIONS) {
      for (const v of d[field] || []) {
        const name = String(v.name || '');
        if (!name) continue;
        cards++;
        const photos: string[] = [v.photo, ...(v.photos || [])].filter(Boolean);
        const provided = v.photos && v.photos.length > 0 ? v.photos : (v.photo ? [v.photo] : undefined);
        const web = webGallery(name, city, cat, v.photo || undefined, provided);
        const app = appGallery(name, cat, photos);
        if (JSON.stringify(web) !== JSON.stringify(app)) out[`${cat}|${city.toLowerCase()}|${name.toLowerCase()}`] = web;
      }
    }
  }
  const esc = (s: string) => JSON.stringify(s); // a JSON string literal is a valid Swift string literal here
  const rows = Object.keys(out).sort().map((k) => `        ${esc(k)}: [${out[k].map(esc).join(', ')}],`);
  const swift = [
    '// Generated by ios-native/scripts/export-cardphotos.sh from the website\'s own PlacePhotosGallery rules. Do not edit.',
    '// The listing cards whose website gallery differs from CityCardPhotos.simple, keyed "category|city|name" (lowercased).',
    'enum CityCardPhotoData {',
    '    static let overrides: [String: [String]] = [',
    ...(rows.length ? rows : ['        :']),
    '    ]',
    '}',
    '',
  ].join('\n');
  fs.writeFileSync(output, swift);
  console.log(`cards ${cards}, differing ${Object.keys(out).length}`);
}
main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
