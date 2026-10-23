// Exports the website's city Things to Do data (components/DeepExperiencesView.tsx) to Resources/citytodo.json:
//   cities["us:<id>" | "dest:<id>"] = { a: Top Attractions in the website's order, t: travelTips }
// Each attraction keeps only what the website's card shows (DeepExperiencesView staticTopAttractions):
//   n name, d description (shortDescription), l location (exactLocation), w website (bookingLink, "N/A" left out),
//   g the card's photo gallery: PlacePhotosGallery's own resolution for this card (name, city = destination.name,
//     category "attraction", fallbackPhoto = verifiedPhoto || photo, photos = [photo]), "" = the navy no-photo tile.
//     Same lines as export-cardphotos.ts webGallery (contributed photos and the live park-photo lookup are not data;
//     the lookup never runs here because these cards always pass photos).
// The destination object is the one the website's city page gets: App.tsx buildBaseDestinations (the live
// /api/destinations answers 404), found by id; getEnrichedAttractions runs on it after NEW_THINGS_TO_DO has loaded.
// Run: sh ios-native/scripts/export-citytodo.sh   (add "--check miami denver <id>" to print names for a spot check)
import { deps } from './export-statepages-deps';
import * as F from './export-citytodo.gen';
import { CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS } from '../../src/caribbeanData';
import { DB_DESTINATIONS } from '../../src/database';
import { getEnrichedAttractions, newThingsReady, getCuratedAttractionPhoto } from '../../src/attractionsDatabase';
import { resolveLocationPhotos } from '../../src/locationPhotos';
import { isValidImageUrl, getHotelFallbackPhoto } from '../../src/cityHeroPhotos';
import { NO_PHOTO_PLACEHOLDER } from '../../src/photoPlaceholder';
import { categoryDefaultPhoto, isPlaceholderPhoto, CATEGORY_DEFAULT_PHOTOS } from '../../src/categoryDefaults';
import * as fs from 'fs';

const { PREMIUM_CITIES, WORLD_DESTINATIONS } = deps;
const SITE = 'https://www.yourkoshertravel.com';
const str = (v: any): string => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '');
const photo = (u: any): string => {
  const s = str(u);
  if (!s || s.startsWith('data:')) return '';
  if (s.startsWith('//')) return 'https:' + s;
  if (s.startsWith('/')) return SITE + s;
  return /^https?:\/\//.test(s) ? s : '';
};


// components/PlacePhotosGallery.tsx basePhotos, line for line (as export-cardphotos.ts webGallery).
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
  return basePhotos.map((p) => (isPlaceholderPhoto(p) ? '' : photo(p)));
}

(async () => {
  await newThingsReady;
  // App.tsx buildBaseDestinations
  const premiumDests = PREMIUM_CITIES.map(F.convertUSCityToDestination);
  const existingIds = new Set([...WORLD_DESTINATIONS.map((d: any) => d.id), ...premiumDests.map((d: any) => d.id)]);
  const destinations: any[] = F.deduplicateDestinations([...WORLD_DESTINATIONS, ...premiumDests, ...DB_DESTINATIONS.filter((d: any) => !existingIds.has(d.id))]);
  const byId = new Map(destinations.map((d: any) => [d.id, d]));

  // The keys the app uses (export-data.ts: cities = PREMIUM_CITIES, destinations = these lists)
  const keyed: [string, any][] = [];
  for (const c of PREMIUM_CITIES as any[]) keyed.push(['us:' + str(c.id), byId.get(c.id) || F.convertUSCityToDestination(c)]);
  const appDests = [...CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS, ...DB_DESTINATIONS.filter((d: any) => d.region === 'North America' || d.region === 'Caribbean' || d.region === 'Central America')];
  for (const d of appDests as any[]) keyed.push(['dest:' + str(d.id), byId.get(d.id) || d]);

  const cities: Record<string, any> = {};
  const full: Record<string, string[]> = {};
  for (const [key, dest] of keyed) {
    if (cities[key]) continue;
    const list = getEnrichedAttractions(dest).map((att: any) => {
      const o: any = { n: str(att.name), d: str(att.description), l: str(att.location) };
      const w = str(att.website); if (w && w !== 'N/A') o.w = w;
      // DeepExperiencesView: fallbackPhoto = verifiedFallbackPhoto || photo; photos = [photo]
      const fb = att.verifiedPhoto || att.photo || undefined;
      o.g = webGallery(str(att.name), str(dest.name), 'attraction', fb, [att.photo]);
      return o;
    }).filter((o: any) => o.n);
    const tips = (Array.isArray(dest.travelTips) ? dest.travelTips : []).map(str).filter(Boolean);
    full[key] = list.map((o: any) => o.n);
    if (!list.length && !tips.length) continue;
    cities[key] = { ...(list.length ? { a: list } : {}), ...(tips.length ? { t: tips } : {}) };
  }
  const out = { generatedAt: new Date().toISOString(), cities };
  fs.writeFileSync(process.argv[2], JSON.stringify(out));
  const vals = Object.values(cities) as any[];
  console.log('keys', keyed.length, 'with data', vals.length, '| attractions', vals.reduce((s, c) => s + (c.a?.length || 0), 0),
    '| with tips', vals.filter(c => c.t).length, '| bytes', fs.statSync(process.argv[2]).size);
  const ci = process.argv.indexOf('--check');
  if (ci > 0) for (const k of process.argv.slice(ci + 1)) {
    const key = k.includes(':') ? k : (full['us:' + k] ? 'us:' + k : 'dest:' + k);
    console.log('CHECK', key, JSON.stringify(full[key] || null), 'tips', (cities[key]?.t || []).length);
  }
})();
