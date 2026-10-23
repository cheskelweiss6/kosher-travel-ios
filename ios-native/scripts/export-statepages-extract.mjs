// Copies the website's own state/country page functions out of src/App.tsx into a temporary TypeScript module, so the
// state-page export runs the website's exact code (not a re-write). Used by export-statepages.sh; the output is deleted
// after the run. Each name is a `const NAME = (...) => { ... };` in App.tsx (top level or inside the App component).
import fs from 'fs';

const [, , appPath, outPath] = process.argv;
const src = fs.readFileSync(appPath, 'utf8');

/** The text of `const NAME = ...;` with its braces matched (strings, template literals and comments skipped). */
function grab(name) {
  const start = src.indexOf(`const ${name} = `);
  if (start < 0) throw new Error(`App.tsx has no "const ${name} = "`);
  let i = src.indexOf('{', src.indexOf('=>', start));
  const stack = [];
  let depth = 0;
  for (; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    const top = stack[stack.length - 1];
    if (top === '`') {
      if (c === '\\') { i++; continue; }
      if (c === '`') { stack.pop(); continue; }
      if (c === '$' && n === '{') { stack.push('${'); i++; continue; }
      continue;
    }
    if (top === "'" || top === '"') {
      if (c === '\\') { i++; continue; }
      if (c === top) stack.pop();
      continue;
    }
    if (c === '/' && n === '/') { i = src.indexOf('\n', i); continue; }
    if (c === '/' && n === '*') { i = src.indexOf('*/', i) + 1; continue; }
    if (c === "'" || c === '"' || c === '`') { stack.push(c); continue; }
    if (c === '{') { if (top === '${') stack.push('{'); else depth++; continue; }
    if (c === '}') {
      if (top === '${') { stack.pop(); continue; }
      if (top === '{') { stack.pop(); continue; }
      depth--;
      if (depth === 0) {
        let end = i + 1;
        while (src[end] && src[end] !== ';' && src[end] !== '\n') end++;
        return src.slice(start, end) + ';';
      }
    }
  }
  throw new Error(`unbalanced ${name}`);
}

/** The body of the state aggregation effect (App.tsx: "// 1. Attractions" up to setIsAggregatingStateData(false)). */
function stateAggregation() {
  const a = src.indexOf('// 1. Attractions');
  const b = src.indexOf('setIsAggregatingStateData(false);', a);
  if (a < 0 || b < 0) throw new Error('state aggregation not found');
  return src.slice(a, b);
}

/** A country aggregation useMemo's body (`const NAME = useMemo(() => { ... }, [`). */
function memo(name) {
  const a = src.indexOf(`const ${name} = useMemo(() => {`);
  if (a < 0) throw new Error(`no useMemo ${name}`);
  const bodyStart = src.indexOf('{', a + `const ${name} = useMemo(() `.length);
  const b = src.indexOf('}, [', bodyStart);
  return src.slice(bodyStart + 1, b);
}

const top = ['convertUSCityToDestination', 'getStateWideDestination', 'deduplicateDestinations', 'isOfficialRestaurant',
  'filterAttractionsByCategory', 'filterCountryAttractionsByCategory'];
const inner = ['getCitiesForState', 'getCitiesForCountry'];
let out = `// GENERATED from src/App.tsx by export-statepages-extract.mjs. Do not edit; deleted after each run.\n/* eslint-disable */\n// @ts-nocheck\n`;
out += `import { deps } from './export-statepages-deps';\nconst { PREMIUM_STATES, PREMIUM_CITIES, US_CITIES, WORLD_DESTINATIONS, PREMIUM_EUROPE, PREMIUM_CARIBBEAN, ALL_KIVREI_TZADIKIM, CURATED_ATTRACTIONS, getEnrichedAttractions, thingsToDoUpdates, airportCoords, calculateFlightTimeClient, getCityHeroImage, CITY_HERO_IMAGES } = deps;\n`;
for (const n of top) out += `export ${grab(n)}\n`;
out += `export const makeArea = (destinations) => {\n${inner.map(grab).join('\n')}\nreturn { ${inner.join(', ')} };\n};\n`;
out += `export const aggregateState = (selectedState, destinations, profile) => {\nconst r = {};\n` +
  ['Attractions', 'Restaurants', 'Chabad', 'Groceries', 'Synagogues', 'Hotels'].map(k => `const setAllState${k} = (v) => { r.${k.toLowerCase()} = v; };`).join('\n') +
  `\n${stateAggregation()}\nreturn r;\n};\n`;
const memos = ['allCountryAttractions', 'allCountryRestaurants', 'allCountryChabad', 'allCountryGroceries', 'allCountrySynagogues', 'allCountryHotels'];
out += `export const aggregateCountry = (selectedCountry, destinations, profile, dataVersion) => ({\n` +
  memos.map(m => `  ${m}: (() => {${memo(m)}})(),`).join('\n') + `\n});\n`;
fs.writeFileSync(outPath, out);
console.log('extracted', top.length + inner.length, 'functions, state + country aggregation');
