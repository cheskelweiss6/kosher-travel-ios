// Exports the app's built-in travel data (compiled into the website as TypeScript) to the JSON the iOS app bundles.
// Run from the repo root:  sh ios-native/scripts/export-data.sh
// Every field beyond the first version's is optional in the app (older JSON still decodes); empty values are left out.
import { PREMIUM_STATES, PREMIUM_CITIES } from '../../src/usData';
import { PREMIUM_CARIBBEAN, CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS } from '../../src/caribbeanData';
import { DB_DESTINATIONS } from '../../src/database';
import { CANADA_DESTINATIONS } from '../../src/canadaDestinations';
import { getCityHeroImage, DEFAULT_TRAVEL_HERO } from '../../src/cityHeroPhotos';
import thingsToDoUpdates from '../../src/thingsToDoUpdates.json';
import * as fs from 'fs';

const SITE = 'https://www.yourkoshertravel.com';
const str = (v: any): string => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '');
const photo = (u: any): string => {
  const s = str(u);
  if (!s || s === DEFAULT_TRAVEL_HERO || s.startsWith('data:')) return '';
  if (s.startsWith('/')) return SITE + s;
  return /^https:\/\//.test(s) ? s : '';
};
// no emoji in the native UI (brand rule): strip pictographs from short labels like "☀️ 84°F"
const noEmoji = (s: string) => s.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]/gu, '').replace(/\s+/g, ' ').trim();
const coord = (v: any) => (typeof v === 'number' && isFinite(v) && v !== 0 ? v : undefined);
const nums = (v: any) => (typeof v === 'number' && isFinite(v) ? v : 0);
const httpsOnly = (u: any) => { const s = str(u); return /^https?:\/\//i.test(s) ? s : ''; };

/** The web's attraction photo fallback (convertUSCityToDestination): thingsToDoUpdates by "name|directions". */
const ttd: Record<string, string> = thingsToDoUpdates as any;
const attractionPhoto = (a: any): string => {
  if (a?.photo) return a.photo;
  const k1 = a.name + '|' + a.directions, k2 = a.name + '|https://maps.google.com/?q=' + encodeURIComponent(a.name);
  return ttd[k1] || ttd[k2] || (Object.entries(ttd).find(([k]) => k.startsWith(a.name + '|')) || [])[1] || '';
};

const venue = (v: any, extra: Record<string, any> = {}) => {
  const photos = (Array.isArray(v?.photos) ? v.photos : []).map(photo).filter(Boolean);
  const first = photo(v?.photo || v?.chabadPhoto) || photos[0] || '';
  const notes = str(v?.notes || v?.note);
  const description = str(v?.description) || notes;
  const out: any = {
    name: str(v?.name), address: str(v?.address), phone: str(v?.phone), website: str(v?.website || v?.link),
    description, photo: first, kashrus: str(v?.kashrus || v?.hechsher), kind: str(v?.type || v?.category),
  };
  const opt: Record<string, any> = {
    photos: Array.from(new Set([first, ...photos].filter(Boolean))),
    hours: str(v?.hours), rabbi: str(v?.rabbi), email: str(v?.email), price: str(v?.price),
    notes: notes && notes !== description ? notes : '', features: str(v?.features),
    directions: httpsOnly(v?.directions), tags: Array.isArray(v?.tags) ? v.tags.map(str).filter(Boolean) : [],
    lat: coord(v?.lat), lng: coord(v?.lng), distance: str(v?.distance),
    shabbatMeals: v?.shabbatMeals === true ? true : undefined,
    isDedicated: typeof v?.isDedicated === 'boolean' ? v.isDedicated : undefined,
    kosherNotes: str(v?.kosherFriendlyNotes), cityName: str(v?.cityName),
    ...extra,
  };
  for (const [k, x] of Object.entries(opt)) {
    if (x === undefined || x === '' || (Array.isArray(x) && x.length === 0)) continue;
    if (k === 'photos' && x.length < 2) continue; // one photo is already `photo`
    out[k] = x;
  }
  return out;
};
const venues = (a: any, f: (v: any) => any = (v) => venue(v)) => (Array.isArray(a) ? a.filter((v: any) => v && str(v.name)).map(f) : []);

/** Mikvah, as the web finds it: only one actually listed among the city's businesses (never made up). */
const mikvahOf = (c: any) => {
  const m = (c.businessesAndServicesList || []).find((s: any) => str(s?.category).toLowerCase().includes('mikvah'));
  if (m) return venue(m);
  if (c.mikvah && str(c.mikvah.name)) return venue(c.mikvah);
  return undefined;
};
const eruvOf = (c: any) => {
  if (c.eruvDetails && str(c.eruvDetails.description)) {
    const e = c.eruvDetails;
    return { name: str(e.name), boundary: str(e.boundary), description: str(e.description), notes: str(e.notes) };
  }
  if (str(c.eruvInfo)) return { name: '', boundary: '', description: str(c.eruvInfo), notes: '' };
  return undefined;
};
const community = (c: any) => {
  const o: any = {
    catering: venues(c.kosherCateringList), rentals: venues(c.vacationRentalsList),
    businesses: venues((c.businessesAndServicesList || []).filter((s: any) => !str(s?.category).toLowerCase().includes('mikvah'))),
    resources: venues(c.communityResourcesList), mikvah: mikvahOf(c), eruv: eruvOf(c),
    hasidic: c.hasidicCommunity ? [str(c.hasidicCommunity.description), str(c.hasidicCommunity.details)].filter(Boolean).join('\n\n') : '',
  };
  for (const k of Object.keys(o)) if (o[k] === undefined || o[k] === '' || (Array.isArray(o[k]) && !o[k].length)) delete o[k];
  return o;
};
const attraction = (a: any) => venue({ ...a, photo: attractionPhoto(a) });

// The destination list the app bundles. One record per id, the first one winning, the way the website's
// buildBaseDestinations drops a database.json copy whose id it already has (Oct 23 2026: Cancun, Mexico City, San Jose
// and the rest of Mexico & Central America were exported twice, the second copy an empty stub).
const APP_DESTINATIONS: any[] = (() => {
  const seen = new Set<string>();
  return [...CARIBBEAN_MEXICO_CENTRAL_AMERICA_DESTINATIONS, ...DB_DESTINATIONS.filter((d: any) => d.region === 'North America' || d.region === 'Caribbean' || d.region === 'Central America'),
    // Canada (Oct 29 2026: Montreal, Toronto; src/canadaDestinations.ts): the region a person sees is 'Canada' (TravelRegions)
    ...CANADA_DESTINATIONS]
    .filter((d: any) => { const id = str(d?.id); if (!id || seen.has(id)) return false; seen.add(id); return true; });
})();

const out = {
  generatedAt: new Date().toISOString(),
  states: PREMIUM_STATES.map((s: any) => ({
    id: str(s.id), name: str(s.name), image: photo(s.image), description: str(s.description),
    lat: nums(s.lat), lng: nums(s.lng), cities: (s.cities || []).map(str),
  })),
  cities: PREMIUM_CITIES.map((c: any) => ({
    id: str(c.id), state: str(c.state), name: str(c.name), description: str(c.description),
    lat: nums(c.lat), lng: nums(c.lng), photo: photo(getCityHeroImage(c.name, c.state)),
    airport: str(c.nearestAirport), airportDistance: str(c.airportDistance), weather: noEmoji(str(c.weather)),
    chabad: venues(c.chabad), restaurants: venues(c.kosherRestaurants), groceries: venues(c.kosherGroceries),
    shuls: venues(c.synagoguesList), hotels: venues(c.hotels), attractions: venues(c.attractions, attraction),
    ...community(c),
  })),
  caribbean: PREMIUM_CARIBBEAN.map((c: any) => ({
    id: str(c.id), name: str(c.name), image: photo(c.image), description: str(c.description),
    lat: nums(c.lat), lng: nums(c.lng), cities: (c.cities || []).map(str),
  })),
  destinations: APP_DESTINATIONS
    .map((d: any) => {
      const lat = coord(d.lat ?? d.coordinates?.lat), lng = coord(d.lng ?? d.coordinates?.lng);
      return {
        id: str(d.id), name: str(d.name), state: str(d.state), country: str(d.country), region: str(d.region),
        image: photo(d.image), description: str(d.description), weather: noEmoji(str(d.weather)),
        airport: str(d.nearestAirport), airportDistance: str(d.airportDistance),
        chabad: venues(d.chabad), restaurants: venues(d.kosherRestaurants), groceries: venues(d.kosherGroceries),
        shuls: venues(d.synagogues && d.synagogues.length ? d.synagogues : d.synagoguesList), hotels: venues(d.hotels), attractions: venues(d.attractions, attraction),
        ...(lat !== undefined && lng !== undefined ? { lat, lng } : {}),
        ...community(d),
      };
    }),
};
fs.writeFileSync(process.argv[2], JSON.stringify(out));
const all = [...out.cities, ...out.destinations] as any[];
const vs = all.flatMap((c) => ['chabad', 'restaurants', 'groceries', 'shuls', 'hotels', 'attractions', 'catering', 'rentals', 'businesses'].flatMap((k) => c[k] || []));
console.log('states', out.states.length, 'cities', out.cities.length, 'caribbean', out.caribbean.length, 'destinations', out.destinations.length,
  '| venues', vs.length, 'with coordinates', vs.filter((v: any) => v.lat !== undefined).length, 'with hours', vs.filter((v: any) => v.hours).length,
  '| mikvah', all.filter((c) => c.mikvah).length, 'eruv', all.filter((c) => c.eruv).length, 'catering', all.filter((c) => c.catering).length,
  'rentals', all.filter((c) => c.rentals).length, 'resources', all.filter((c) => c.resources).length);
