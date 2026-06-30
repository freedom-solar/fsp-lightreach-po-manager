import React, { useState, useEffect } from 'react';
import { Box, Container, Tab, Tabs } from '@mui/material';
import RegionView from './po_generation/RegionView';

const REGIONS = ['Austin', 'Dallas', 'Houston', 'San Antonio', 'Orlando', 'Tampa'];

// PO Generation feature: per-region tabs that drive PO generation. Extracted
// from Dashboard so the top-level nav can host additional dashboards.
export default function POGenerationView() {
  // Initialize selected region from URL query params
  const getInitialRegion = () => {
    const params = new URLSearchParams(window.location.search);
    const regionParam = params.get('region');
    if (regionParam) {
      const index = REGIONS.findIndex(r => r.toLowerCase() === regionParam.toLowerCase());
      if (index !== -1) return index;
    }
    return 0; // Default to Austin
  };

  const [selectedRegion, setSelectedRegion] = useState(getInitialRegion);

  // Update URL when region changes
  useEffect(() => {
    const region = REGIONS[selectedRegion];
    const url = new URL(window.location);
    url.searchParams.set('region', region);
    window.history.pushState({}, '', url);
  }, [selectedRegion]);

  const handleRegionChange = (event, newValue) => {
    setSelectedRegion(newValue);
  };

  return (
    <>
      <Box sx={{ borderBottom: 1, borderColor: 'divider', bgcolor: 'background.paper' }}>
        <Container maxWidth="xl">
          <Tabs
            value={selectedRegion}
            onChange={handleRegionChange}
            aria-label="region tabs"
          >
            {REGIONS.map((region) => (
              <Tab key={region} label={region} />
            ))}
          </Tabs>
        </Container>
      </Box>

      <Container maxWidth="xl" sx={{ flexGrow: 1, py: 3 }}>
        {REGIONS.map((region, index) => (
          <div
            key={region}
            role="tabpanel"
            hidden={selectedRegion !== index}
            id={`region-tabpanel-${index}`}
          >
            {selectedRegion === index && <RegionView region={region} />}
          </div>
        ))}
      </Container>
    </>
  );
}