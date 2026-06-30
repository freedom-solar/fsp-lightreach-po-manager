// Shared region taxonomy for the dashboards. NetSuite locations roll up into a
// fixed set of regions (San Antonio is part of Austin; Dallas shows as DFW),
// Charlotte is excluded entirely.

export const REGIONS = ['All', 'Commercial', 'Austin', 'DFW', 'Houston', 'Orlando', 'Tampa'];

const LOCATION_TO_REGION = {
  Commercial: 'Commercial',
  Austin: 'Austin',
  'San Antonio': 'Austin',
  Dallas: 'DFW',
  Houston: 'Houston',
  Orlando: 'Orlando',
  Tampa: 'Tampa',
};

const IGNORED_LOCATIONS = ['Charlotte'];

const baseLocation = (location) =>
  String(location || '').replace(/\s*-\s*Consignment$/i, '').trim();

// Maps a NetSuite location (incl. "X - Consignment" variants) to a region tab,
// or null if it isn't part of one of the fixed regions (shown only under "All").
export const regionForLocation = (location) => {
  if (!location) return null;
  return LOCATION_TO_REGION[baseLocation(location)] || null;
};

// Locations excluded from the dashboards entirely (even under "All").
export const isIgnoredLocation = (location) => {
  if (!location) return false;
  return IGNORED_LOCATIONS.includes(baseLocation(location));
};