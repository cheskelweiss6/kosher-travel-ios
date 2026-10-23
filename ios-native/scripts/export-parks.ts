// Exports the website's parks data (state parks, national parks, tribal & scenic landmarks) to the JSON the iOS app bundles.
// Run from the website repo root (same layout as export-data.ts):  sh ios-native/scripts/export-parks.sh
// The website merges the files exactly like this (src/stateParksData.ts, src/nationalParksData.ts,
// src/tribalAndScenicParksData.ts); the app reads the merged result, keyed like the website's own lookups.
// Only the fields the website's park cards and sheets show are kept; empty values are left out.
import { STATE_PARKS_DATABASE } from '../../src/stateParksData';
import { NATIONAL_PARKS_DATABASE } from '../../src/nationalParksData';
import { TRIBAL_SCENIC_LANDMARKS_DATABASE } from '../../src/tribalAndScenicParksData';
import * as fs from 'fs';

const IMG_BASE = 'https://kosher-travel-img.sites.tab.bot';
const str = (v: any): string => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '');
const photo = (u: any): string => {
  const s = str(u);
  if (!s || s.startsWith('data:')) return '';
  if (/^\/(wm|venues)\//.test(s)) return IMG_BASE + s;
  if (s.startsWith('/')) return 'https://www.yourkoshertravel.com' + s;
  return /^https?:\/\//.test(s) ? s : '';
};
const list = (v: any): string[] => (Array.isArray(v) ? v.map(str).filter(Boolean) : []);
const prune = (o: any) => {
  for (const k of Object.keys(o)) {
    const v = o[k];
    if (v === '' || v === undefined || v === null || (Array.isArray(v) && v.length === 0)) delete o[k];
    else if (typeof v === 'object' && !Array.isArray(v)) { prune(v); if (Object.keys(v).length === 0) delete o[k]; }
  }
  return o;
};
// hikingTrails: { name, difficulty, length, description } (web activities also read `distance` when `length` is missing)
const trails = (v: any) => (Array.isArray(v) ? v : []).map((t: any) => typeof t === 'string'
  ? { name: str(t) }
  : { name: str(t?.name), difficulty: str(t?.difficulty), length: str(t?.length) || str(t?.distance), description: str(t?.description) });
// scenicDrives: a string stays the name (the web shows it as written); an object keeps name / length / description
const drives = (v: any) => (Array.isArray(v) ? v : []).map((d: any) => typeof d === 'string'
  ? { name: str(d) }
  : { name: str(d?.name), length: str(d?.length), description: str(d?.description) });
// rangerPrograms: the web shows a string as written, an object as "name - info"
const ranger = (v: any) => (Array.isArray(v) ? v : []).map((p: any) => typeof p === 'string'
  ? str(p) : `${str(p?.name)}${str(p?.info) ? ` - ${str(p?.info)}` : ''}`).filter(Boolean);
const vc = (v: any) => ({ name: str(v?.name), info: str(v?.info), hours: str(v?.hours), phone: str(v?.phone) });

const stateOut: Record<string, any[]> = {};
for (const [key, parks] of Object.entries(STATE_PARKS_DATABASE)) {
  stateOut[key] = (parks as any[]).map(p => prune({
    id: str(p.id), name: str(p.name), image: photo(p.image), photoGallery: (p.photoGallery || []).map(photo).filter(Boolean),
    shortDescription: str(p.shortDescription), fullDescription: str(p.fullDescription), thingsToDo: list(p.thingsToDo),
    hikingTrails: trails(p.hikingTrails), campingInfo: str(p.campingInfo), fishingBoating: str(p.fishingBoating),
    wildlife: list(p.wildlife), visitorCenter: vc(p.visitorCenter), hours: str(p.hours), entranceFees: str(p.entranceFees),
    address: str(p.address), googleMapsLocation: str(p.googleMapsLocation), officialWebsite: str(p.officialWebsite),
    bestTimeToVisit: str(p.bestTimeToVisit), tips: list(p.tips), nearbyAttractions: list(p.nearbyAttractions),
  }));
}
const national = (p: any) => prune({
  id: str(p.id), name: str(p.name), designation: str(p.designation), image: photo(p.image),
  photoGallery: (p.photoGallery || []).map(photo).filter(Boolean),
  shortDescription: str(p.shortDescription), fullDescription: str(p.fullDescription), thingsToDo: list(p.thingsToDo),
  hikingTrails: trails(p.hikingTrails), scenicDrives: drives(p.scenicDrives), visitorCenter: vc(p.visitorCenter),
  rangerPrograms: ranger(p.rangerPrograms), campingInfo: str(p.campingInfo), wildlife: list(p.wildlife),
  bestViewpoints: list(p.bestViewpoints), entranceFees: str(p.entranceFees), hours: str(p.hours), address: str(p.address),
  googleMapsLocation: str(p.googleMapsLocation), officialWebsite: str(p.officialWebsite), bestTimeToVisit: str(p.bestTimeToVisit),
  accessibilityInfo: str(p.accessibilityInfo), travelTips: list(p.travelTips), nearbyAttractions: list(p.nearbyAttractions),
});
const nationalOut: Record<string, any[]> = {};
for (const [key, parks] of Object.entries(NATIONAL_PARKS_DATABASE)) nationalOut[key] = (parks as any[]).map(national);
const tribalOut: Record<string, any[]> = {};
for (const [key, parks] of Object.entries(TRIBAL_SCENIC_LANDMARKS_DATABASE)) tribalOut[key] = (parks as any[]).map(national);

const out = process.argv[2] || 'ios-native/KosherTravel/Resources/parks.json';
const json = JSON.stringify({ version: 1, state: stateOut, national: nationalOut, tribal: tribalOut });
fs.writeFileSync(out, json);
const n = (o: Record<string, any[]>) => Object.values(o).reduce((a, l) => a + l.length, 0);
console.log(`parks.json: ${(json.length / 1024).toFixed(0)} KB, ${n(stateOut)} state parks, ${n(nationalOut)} national sites, ${n(tribalOut)} tribal & scenic`);
