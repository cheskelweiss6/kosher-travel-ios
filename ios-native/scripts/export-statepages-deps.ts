// What the website's state/country page code (copied out of App.tsx by export-statepages-extract.mjs) reads.
import { PREMIUM_STATES, PREMIUM_CITIES, US_CITIES } from '../../src/usData';
import { PREMIUM_CARIBBEAN } from '../../src/caribbeanData';
import { WORLD_DESTINATIONS } from '../../src/data';
import { PREMIUM_EUROPE } from '../../src/europeData';
import { ALL_KIVREI_TZADIKIM } from '../../src/kivreiTzadikimDatabase';
import { CURATED_ATTRACTIONS, getEnrichedAttractions } from '../../src/attractionsDatabase';
import { getCityHeroImage, CITY_HERO_IMAGES } from '../../src/cityHeroPhotos';
import thingsToDoUpdates from '../../src/thingsToDoUpdates.json';

export const deps: any = {
  PREMIUM_STATES, PREMIUM_CITIES, US_CITIES, WORLD_DESTINATIONS, PREMIUM_EUROPE, PREMIUM_CARIBBEAN, ALL_KIVREI_TZADIKIM,
  CURATED_ATTRACTIONS, getEnrichedAttractions, thingsToDoUpdates, getCityHeroImage, CITY_HERO_IMAGES,
  // flight times are not part of the export (the app computes travel times itself)
  airportCoords: {}, calculateFlightTimeClient: () => '',
};
