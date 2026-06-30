import React, { useState, useEffect } from 'react';
import {
  AppBar,
  Box,
  Tab,
  Tabs,
  Toolbar,
  Typography,
  IconButton,
} from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import LogoutIcon from '@mui/icons-material/Logout';
import POGenerationView from './POGenerationView';
import ProcurementDashboard from './ProcurementDashboard';

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

// Top-level feature views. Add new dashboards here (e.g. Inventory) to surface
// them as tabs in the app bar.
const VIEWS = [
  { key: 'po-generation', label: 'PO Generation', Component: POGenerationView },
  { key: 'procurement', label: 'Dashboard', Component: ProcurementDashboard },
];

export default function Dashboard() {
  // Get logo URL from data attribute set by Rails asset pipeline
  const logoUrl = document.getElementById('react-root')?.getAttribute('data-logo-url');

  // Initialize selected view from URL query params
  const getInitialView = () => {
    const params = new URLSearchParams(window.location.search);
    const viewParam = params.get('view');
    const index = VIEWS.findIndex(v => v.key === viewParam);
    return index !== -1 ? index : 0;
  };

  const [selectedView, setSelectedView] = useState(getInitialView);

  // Update URL when view changes
  useEffect(() => {
    const url = new URL(window.location);
    url.searchParams.set('view', VIEWS[selectedView].key);
    window.history.pushState({}, '', url);
  }, [selectedView]);

  const handleViewChange = (event, newValue) => {
    setSelectedView(newValue);
  };

  const handleLogout = () => {
    if (confirm('Are you sure you want to sign out?')) {
      window.location.href = '/users/sign_out';
    }
  };

  const ActiveComponent = VIEWS[selectedView].Component;

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
                PO Tool
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
          <Tabs
            value={selectedView}
            onChange={handleViewChange}
            aria-label="view tabs"
            textColor="inherit"
            indicatorColor="primary"
            sx={{ px: 2, borderTop: 1, borderColor: 'divider' }}
          >
            {VIEWS.map((view) => (
              <Tab key={view.key} label={view.label} />
            ))}
          </Tabs>
        </AppBar>

        <ActiveComponent />
      </Box>
    </ThemeProvider>
  );
}