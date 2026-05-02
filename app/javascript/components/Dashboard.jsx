import React, { useState, useEffect } from 'react';
import {
  AppBar,
  Box,
  Container,
  Tab,
  Tabs,
  Toolbar,
  Typography,
  Button,
  IconButton,
} from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import LogoutIcon from '@mui/icons-material/Logout';
import RegionView from './po_generation/RegionView';

// Freedom Power Brand Colors
const BRAND = {
  freedomBlue: '#252F38',
  freedomOrange: '#F98A3C',
};

const darkTheme = createTheme({
  palette: {
    mode: 'dark',
    background: {
      default: '#0d0d1a',
      paper: '#1a1a2e'
    },
    primary: {
      main: BRAND.freedomOrange
    },
    secondary: {
      main: BRAND.freedomBlue
    }
  },
  typography: {
    fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif'
  }
});

const REGIONS = ['Austin', 'Dallas', 'Houston', 'San Antonio', 'Orlando', 'Tampa'];

export default function Dashboard() {
  // Get logo URL from data attribute set by Rails asset pipeline
  const logoUrl = document.getElementById('react-root')?.getAttribute('data-logo-url');

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

  const handleLogout = () => {
    if (confirm('Are you sure you want to sign out?')) {
      window.location.href = '/users/sign_out';
    }
  };

  return (
    <ThemeProvider theme={darkTheme}>
      <CssBaseline />
      <Box sx={{ display: 'flex', flexDirection: 'column', minHeight: '100vh' }}>
        <AppBar
          position="static"
          sx={{
            backgroundColor: '#1a1a2e',
            boxShadow: '0 2px 8px rgba(0,0,0,0.3)'
          }}
        >
          <Toolbar>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Box
                component="img"
                src={logoUrl}
                alt="Freedom Power"
                sx={{ height: 36 }}
              />
              <Typography variant="h6" component="div" sx={{ color: '#fff', fontWeight: 500 }}>
                Lightreach PO Manager
              </Typography>
            </Box>
            <Box sx={{ flexGrow: 1 }} />
            <IconButton
              color="inherit"
              onClick={handleLogout}
              title="Sign out"
            >
              <LogoutIcon />
            </IconButton>
          </Toolbar>
        </AppBar>

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
      </Box>
    </ThemeProvider>
  );
}
