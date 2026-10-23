// Exports what the website's United States, state, Caribbean and country/island pages show (src/App.tsx) to the JSON
// the native app bundles: Features/StatePage/statepages.json. It runs the website's own functions (copied out of App.tsx
// by export-statepages-extract.mjs): getCitiesForState, the state aggregation (attractions, restaurants, Chabad,
// groceries, shuls, hotels from every city in the state), getCitiesForCountry, the country aggregations,
// getStateWideDestination, deduplicateDestinations and the base destination list (buildBaseDestinations).
// Run from the website repo root:  sh ios-native/scripts/export-statepages.sh
import { deps } from './export-statepages-deps';
import * as F from './export-statepages.gen';
import { CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS } from '../../src/caribbeanData';
import { DB_DESTINATIONS } from '../../src/database';
import { DEFAULT_TRAVEL_HERO } from '../../src/cityHeroPhotos';
import { buildSearchIndex } from '../../src/searchIndex';
import { getNewThingsToDoFor } from '../../src/attractionsDatabase';
import * as fs from 'fs';

const { PREMIUM_STATES, PREMIUM_CITIES, US_CITIES, WORLD_DESTINATIONS, PREMIUM_CARIBBEAN, CURATED_ATTRACTIONS } = deps;
const SITE = 'https://www.yourkoshertravel.com';
const str = (v: any): string => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '');
const photo = (u: any): string => {
  const s = str(u);
  if (!s || s === DEFAULT_TRAVEL_HERO || s.startsWith('data:')) return '';
  if (s.startsWith('/')) return SITE + s;
  return /^https?:\/\//.test(s) ? s : '';
};
const noEmoji = (s: string) => s.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]/gu, '').replace(/\s+/g, ' ').trim();

// App.tsx buildBaseDestinations (the live /api/destinations answers 404, so this is the list the website shows)
const premiumDests = PREMIUM_CITIES.map(F.convertUSCityToDestination);
const existingIds = new Set([...WORLD_DESTINATIONS.map((d: any) => d.id), ...premiumDests.map((d: any) => d.id)]);
const destinations = F.deduplicateDestinations([...WORLD_DESTINATIONS, ...premiumDests, ...DB_DESTINATIONS.filter((d: any) => !existingIds.has(d.id))]);
const area = F.makeArea(destinations);
const profile = { homeAirport: 'New York' };

// Which native page a card opens: the app's explore.json carries PREMIUM_CITIES as "us:<id>" and
// CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS + DB_DESTINATIONS (North America / Caribbean / Central America) as "dest:<id>".
const usIds = new Set(PREMIUM_CITIES.map((c: any) => c.id));
const destIds = new Set([...CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS, ...DB_DESTINATIONS.filter((d: any) =>
  d.region === 'North America' || d.region === 'Caribbean' || d.region === 'Central America')].map((d: any) => d.id));
const routeKey = (d: any) => (usIds.has(d.id) ? `us:${d.id}` : destIds.has(d.id) ? `dest:${d.id}` : '');

const cityLowerHas = (d: any, key: 'kosherGroceries' | 'chabad') => {
  const cityLower = d.name.toLowerCase().trim();
  // renderDestinationCard: the destination's own list, or a US_CITIES entry of that name (places from the live API are
  // read by the app at run time, not here)
  return (d[key] && d[key].length > 0) || US_CITIES.some((c: any) => c.name.toLowerCase() === cityLower && c[key] && c[key].length > 0);
};
// renderDestinationCard: the photo, else the city hero photo; the subtitle line
const card = (d: any, stateWide = false) => {
  const cityLower = d.name.toLowerCase().trim();
  const sub = d.state && d.state.toLowerCase() !== (d.country || '').toLowerCase() && d.state.toLowerCase() !== d.name.toLowerCase()
    ? `${d.state}, ${d.country || 'USA'}`
    : (d.name && d.country && d.name.toLowerCase() !== d.country.toLowerCase() ? `${d.name}, ${d.country}` : d.country || 'USA');
  const hero = deps.getCityHeroImage(cityLower, d.state || d.country, deps.CITY_HERO_IMAGES);
  const out: any = {
    id: d.id, key: stateWide ? '' : routeKey(d), name: d.name, sub, state: str(d.state), country: str(d.country), region: str(d.region),
    image: photo(d.image) || photo(hero), groc: !!cityLowerHas(d, 'kosherGroceries'), chab: !!cityLowerHas(d, 'chabad'),
  };
  // the hero photo stands in when the destination's own photo fails to load (handleCityHeroImageError)
  if (photo(hero) && photo(hero) !== out.image) out.fallback = photo(hero);
  if (stateWide) out.wide = true;
  return out;
};

// One listing, with the fields the state/country cards and the place sheet read. `destId` is the city it came from
// (the place sheet's review ids use it, like the city page's).
const byName = new Map<string, any>();
for (const d of destinations) byName.set(`${d.name.toLowerCase().trim()}|${(d.state || d.country || '').toLowerCase().trim()}`, d);
const destIdFor = (cityName: string, region: string) => {
  const d = byName.get(`${(cityName || '').toLowerCase().trim()}|${region.toLowerCase().trim()}`);
  return d ? d.id : '';
};
const listing = (x: any, region: string) => {
  const photos = (Array.isArray(x?.photos) ? x.photos : []).map(photo).filter(Boolean);
  const o: any = {
    name: str(x.name), address: str(x.address), phone: str(x.phone), website: str(x.website), description: str(x.description),
    photo: photo(x.photo) || photos[0] || '', kashrus: str(x.kashrus || x.hechsher), kind: str(x.type || x.category),
  };
  const opt: Record<string, any> = {
    photos: photos.length ? photos : undefined, rabbi: str(x.rabbi) || undefined, shabbatMeals: x.shabbatMeals ? true : undefined,
    tags: Array.isArray(x.tags) && x.tags.length ? x.tags.map(str).filter(Boolean) : undefined, nusach: str(x.nusach) || undefined,
    link: str(x.link) || undefined, directions: str(x.directions) || undefined, location: str(x.location) || undefined,
    hours: str(x.hours) || undefined, email: str(x.email) || undefined, price: str(x.price) || undefined,
    notes: str(x.notes || x.note) || undefined, kosherNotes: str(x.kosherFriendlyNotes) || undefined,
    cityName: str(x.cityName) || undefined, destId: destIdFor(x.cityName, region) || undefined,
  };
  for (const [k, v] of Object.entries(opt)) if (v !== undefined) o[k] = v;
  // empty text is left out (the app reads a missing field as empty)
  for (const k of ['address', 'phone', 'website', 'description', 'photo', 'kashrus', 'kind']) if (!o[k]) delete o[k];
  return o;
};

const states: Record<string, any> = {};
for (const s of PREMIUM_STATES) {
  const cities = area.getCitiesForState(s.name);
  const agg = F.aggregateState(s.name, destinations, profile);
  states[s.name] = {
    cities: cities.map((d: any) => card(d)),
    attractions: agg.attractions.map((a: any) => listing(a, s.name)),
    chabad: agg.chabad.map((a: any) => listing(a, s.name)),
    groceries: agg.groceries.map((a: any) => listing(a, s.name)),
    shuls: agg.synagogues.map((a: any) => listing(a, s.name)),
    hotels: agg.hotels.map((a: any) => listing(a, s.name)),
  };
}

// Countries: the Caribbean list (PREMIUM_CARIBBEAN, Central America included) and each country page.
const EXCLUDE_WIDE = ["costa rica", "guatemala", "honduras", "nicaragua", "british virgin islands", "grenada", "dominica", "el salvador",
  "saint kitts and nevis", "saba", "montserrat", "saint martin", "puerto rico", "jamaica", "trinidad and tobago", "sint eustatius",
  "saint vincent and the grenadines", "belize", "saint barthelemy", "saint barthélemy", "panama", "saint lucia", "guadeloupe", "haiti",
  "martinique", "bermuda", "us virgin islands", "u.s. virgin islands", "united states virgin islands", "turks and caicos",
  "turks and caicos islands", "curacao", "curaçao"];
const countries: Record<string, any> = {};
for (const c of PREMIUM_CARIBBEAN) {
  const name = c.name;
  // App.tsx country page: destinations of the country, one card per name + country
  const seen = new Set<string>();
  const finalDests = destinations.filter((d: any) => d.country === name).filter((d: any) => {
    const k = `${d.name.toLowerCase().trim()}|${d.country.toLowerCase().trim()}`;
    if (seen.has(k)) return false; seen.add(k); return true;
  });
  const wide = CURATED_ATTRACTIONS[name.toLowerCase()] && !EXCLUDE_WIDE.includes(name.toLowerCase()) && finalDests.length > 0
    ? card(F.getStateWideDestination(name, profile), true) : null;
  const agg = F.aggregateCountry(name, destinations, profile, 0);
  countries[name] = {
    cityCount: area.getCitiesForCountry(name, 'Caribbean').length,
    cities: finalDests.map((d: any) => card(d)),
    wide,
    attractions: agg.allCountryAttractions.map((a: any) => listing(a, name)),
    restaurants: agg.allCountryRestaurants.map((a: any) => listing(a, name)),
    chabad: agg.allCountryChabad.map((a: any) => listing(a, name)),
  };
}

const out = {
  generatedAt: new Date().toISOString(),
  // United States page: the state circles (PREMIUM_STATES order, the city count is getCitiesForState's length)
  usStates: PREMIUM_STATES.map((s: any) => ({ id: s.id, name: s.name, image: photo(s.image), description: str(s.description),
    cityCount: area.getCitiesForState(s.name).length })),
  // Caribbean page: the island circles (PREMIUM_CARIBBEAN order, the count is getCitiesForCountry's length)
  caribbean: PREMIUM_CARIBBEAN.map((c: any) => ({ id: c.id, name: c.name, image: photo(c.image), description: str(c.description),
    lat: c.lat, lng: c.lng, cityCount: countries[c.name].cityCount })),
  states, countries,
};
const file = process.argv[2] || 'ios-native/KosherTravel/Features/StatePage/statepages.json';
fs.writeFileSync(file, JSON.stringify(out));
const n = (k: string) => Object.values(states).reduce((a: number, s: any) => a + s[k].length, 0);
console.log('usStates', out.usStates.length, 'caribbean', out.caribbean.length, 'state cities', n('cities'), 'attractions', n('attractions'),
  'chabad', n('chabad'), 'groceries', n('groceries'), 'shuls', n('shuls'), 'hotels', n('hotels'),
  'no-page cards', Object.values(states).flatMap((s: any) => s.cities).filter((c: any) => !c.key).map((c: any) => c.name).join('; '),
  'bytes', fs.statSync(file).size);

// The in-page search's listing index (App.tsx getStoriesSearchIdx = buildSearchIndex(destinations, US_CITIES,
// convertUSCityToDestination, searchAttractionsFor)), for the regions these pages cover. The words are the website's own
// normalised word lists, so matching in the app scores exactly as on the website. Places travelers tagged are added by
// the app at run time (searchAttractionsFor's live part).
const searchAttractionsFor = (d: any) => [...(CURATED_ATTRACTIONS[d.name.toLowerCase().trim()] || []), ...getNewThingsToDoFor(d)];
const idx = buildSearchIndex(destinations, US_CITIES as any, F.convertUSCityToDestination, searchAttractionsFor);
const REGIONS = new Set(['North America', 'Caribbean', 'Central America']);
const dests: any[] = [];
const destPos = new Map<any, number>();
const destRef = (d: any) => {
  if (destPos.has(d)) return destPos.get(d)!;
  const sub = d.state ? `${d.state}, ${d.country}` : d.country;
  dests.push({ id: d.id, key: routeKey(d), name: d.name, state: str(d.state), country: str(d.country), region: str(d.region), sub, image: photo(d.image) });
  destPos.set(d, dests.length - 1);
  return dests.length - 1;
};
const thumbOf = (e: any) => {
  const it = e.item || {};
  const p = it.photo || it.image || (Array.isArray(it.photos) && it.photos[0]) || (e.kind === 'destination' ? e.dest?.image : '');
  return typeof p === 'string' && /^(https?:|\/)/.test(p) ? photo(p) : '';
};
const entries = idx.filter((e: any) => e.dest && REGIONS.has(e.dest.region)).map((e: any) => {
  const o: any = { k: e.kind, n: e.name, s: e.subtitle, c: e.cityName, d: destRef(e.dest),
    nw: e.nameWords.join(' '), tw: e.typeWords.join(' '), pw: e.placeWords.join(' '), ew: e.extraWords.join(' ') };
  if (e.aliasNorm) o.an = e.aliasNorm;
  if (!o.ew) delete o.ew;
  const th = thumbOf(e); if (th) o.th = th;
  if (e.kind !== 'destination' && e.kind !== 'mikvah' && e.item && !e.item.sharedSight) {
    const l = listing({ ...e.item, cityName: e.cityName }, e.dest.state || e.dest.country || '');
    l.destId = e.dest.id;
    if (l.description && l.description.length > 240) l.description = l.description.slice(0, 237).trimEnd() + '…';
    o.it = l;
    if (o.th && o.th === l.photo) delete o.th;
  }
  return o;
});
const sfile = (process.argv[2] || 'ios-native/KosherTravel/Features/StatePage/statepages.json').replace('statepages.json', 'statesearch.json');
fs.writeFileSync(sfile, JSON.stringify({ generatedAt: new Date().toISOString(), dests, entries }));
console.log('search entries', entries.length, 'dests', dests.length, 'bytes', fs.statSync(sfile).size);
