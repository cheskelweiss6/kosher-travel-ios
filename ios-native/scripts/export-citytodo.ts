// Exports the website's city Things to Do data (components/DeepExperiencesView.tsx) to Resources/citytodo.json:
//   cities["us:<id>" | "dest:<id>"] = { a: Top Attractions in the website's order, t: travelTips }
// Each attraction keeps only what the website's card shows (DeepExperiencesView staticTopAttractions):
//   n name, d description (shortDescription), l location (exactLocation), w website (bookingLink, "N/A" left out),
//   p photo (the card's PlacePhotosGallery gets photos: [p]), vp verifiedPhoto (its fallbackPhoto, kept when it differs from p).
// The destination object is the one the website's city page gets: App.tsx buildBaseDestinations (the live
// /api/destinations answers 404), found by id; getEnrichedAttractions runs on it after NEW_THINGS_TO_DO has loaded.
// Run: sh ios-native/scripts/export-citytodo.sh   (add "--check miami denver <id>" to print names for a spot check)
import { deps } from './export-statepages-deps';
import * as F from './export-citytodo.gen';
import { CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS } from '../../src/caribbeanData';
import { DB_DESTINATIONS } from '../../src/database';
import { getEnrichedAttractions, newThingsReady } from '../../src/attractionsDatabase';
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
      const p = photo(att.photo);
      const vp = photo(att.verifiedPhoto);
      const o: any = { n: str(att.name), d: str(att.description), l: str(att.location) };
      const w = str(att.website); if (w && w !== 'N/A') o.w = w;
      if (p) o.p = p;
      if (vp && vp !== p) o.vp = vp;
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
