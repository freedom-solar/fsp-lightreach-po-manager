import React from 'react';
import {
  AppBar,
  Box,
  Card,
  CardActionArea,
  CardContent,
  Container,
  CssBaseline,
  Paper,
  Toolbar,
  Typography,
} from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import HomeIcon from '@mui/icons-material/Home';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import PostAddIcon from '@mui/icons-material/PostAdd';
import AssessmentIcon from '@mui/icons-material/Assessment';
import CampaignIcon from '@mui/icons-material/Campaign';
import EngineeringIcon from '@mui/icons-material/Engineering';
import WbSunnyIcon from '@mui/icons-material/WbSunny';
import VerifiedIcon from '@mui/icons-material/Verified';
import CameraAltIcon from '@mui/icons-material/CameraAlt';
import PaymentsIcon from '@mui/icons-material/Payments';
import DashboardIcon from '@mui/icons-material/Dashboard';
import BoltIcon from '@mui/icons-material/Bolt';

// Freedom Power Brand Colors
const BRAND = {
  freedomBlue: '#252F38',
  freedomOrange: '#F98A3C',
};

const darkTheme = createTheme({
  palette: {
    mode: 'dark',
    background: { default: '#0d0d1a', paper: '#1a1a2e' },
    primary: { main: BRAND.freedomOrange },
    secondary: { main: BRAND.freedomBlue },
  },
  typography: {
    fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif',
  },
});

// This app's own views (same-origin links into the SPA).
const APP_VIEWS = [
  {
    title: 'PO Generation',
    description: 'Generate purchase orders by region from scheduled installs.',
    icon: PostAddIcon,
    url: '/?view=po-generation',
  },
  {
    title: 'Procurement Dashboard',
    description: 'Open Contract Labor POs by class, location, and vendor with aging.',
    icon: AssessmentIcon,
    url: '/?view=procurement',
  },
];

// Other Freedom Power dashboards (separate apps).
const DASHBOARDS = [
  {
    title: 'Sales & Marketing Dash',
    description: 'Advertising, set-to-close, closing ratio, and EC pipeline.',
    icon: CampaignIcon,
    url: 'https://marketing-dash.gofreedompower.com',
  },
  {
    title: 'Operations Dashboard',
    description: 'Resource utilization, crew scheduling, quality, and Lightreach collections.',
    icon: EngineeringIcon,
    url: 'https://fsp-resource-dash.gofreedompower.com',
  },
  {
    title: 'Sunrise',
    description: 'Project management and customer records.',
    icon: WbSunnyIcon,
    url: 'https://sunrise.gofreedompower.com',
  },
  {
    title: 'Lightreach Site Capture Verification',
    description: 'Verify Lightreach site capture submissions.',
    icon: VerifiedIcon,
    url: 'https://give-a-damn.gofreedompower.com',
  },
];

// Third-party tools.
const EXTERNAL_TOOLS = [
  { title: 'Site Capture', icon: CameraAltIcon, url: 'https://solar.sitecapture.com' },
  { title: 'Palmetto Lightreach Portal', icon: PaymentsIcon, url: 'https://palmetto.finance' },
  {
    title: 'HDM Portal',
    icon: DashboardIcon,
    url: 'https://hdmcadmin1.zohocreatorportal.com/#Page:Sales_Dashboard_V2',
  },
  { title: 'Flic Portal', icon: BoltIcon, url: 'https://flicportal.com/auth/login' },
  { title: 'Captivate IQ', icon: DashboardIcon, url: 'https://app.captivateiq.com/login' },
];

const cardGrid = {
  display: 'grid',
  gridTemplateColumns: { xs: '1fr', sm: '1fr 1fr', md: 'repeat(3, 1fr)' },
  gap: 3,
};

const LinkCard = ({ title, description, url, icon: Icon, external, accent = true }) => (
  <Card
    sx={{
      backgroundColor: '#1a1a2e',
      border: '1px solid #333',
      height: '100%',
      transition: 'all 0.2s ease',
      '&:hover': {
        borderColor: accent ? BRAND.freedomOrange : '#666',
        transform: 'translateY(-2px)',
        boxShadow: accent
          ? '0 4px 20px rgba(249, 138, 60, 0.2)'
          : '0 4px 20px rgba(0, 0, 0, 0.3)',
      },
    }}
  >
    <CardActionArea
      component="a"
      href={url}
      {...(external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
      sx={{ height: '100%' }}
    >
      <CardContent sx={{ p: 3 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
            <Box
              sx={{
                width: 48,
                height: 48,
                borderRadius: 2,
                backgroundColor: accent ? 'rgba(249, 138, 60, 0.15)' : 'rgba(255, 255, 255, 0.08)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <Icon sx={{ color: accent ? BRAND.freedomOrange : '#999', fontSize: 28 }} />
            </Box>
            <Typography variant="h6" sx={{ color: '#fff', fontWeight: 600 }}>
              {title}
            </Typography>
          </Box>
          {external && <OpenInNewIcon sx={{ color: '#666', fontSize: 18 }} />}
        </Box>
        {description && (
          <Typography variant="body2" sx={{ color: '#999' }}>
            {description}
          </Typography>
        )}
      </CardContent>
    </CardActionArea>
  </Card>
);

const Section = ({ title, children }) => (
  <Paper sx={{ p: 3, mb: 4, backgroundColor: 'background.paper' }}>
    <Typography variant="h6" sx={{ color: '#fff', mb: 3 }}>
      {title}
    </Typography>
    <Box sx={cardGrid}>{children}</Box>
  </Paper>
);

export default function LinkHub({ logoUrl }) {
  return (
    <ThemeProvider theme={darkTheme}>
      <CssBaseline />
      <AppBar
        position="static"
        sx={{ backgroundColor: '#1a1a2e', boxShadow: '0 2px 8px rgba(0,0,0,0.3)' }}
      >
        <Toolbar>
          <Box
            component="a"
            href="/"
            sx={{ display: 'flex', alignItems: 'center', gap: 2, textDecoration: 'none' }}
          >
            {logoUrl && (
              <Box component="img" src={logoUrl} alt="Freedom Power" sx={{ height: 36 }} />
            )}
            <Typography variant="h6" sx={{ color: '#fff', fontWeight: 500 }}>
              PO Tool
            </Typography>
          </Box>
        </Toolbar>
      </AppBar>

      <Box sx={{ backgroundColor: 'background.default', minHeight: 'calc(100vh - 64px)' }}>
        <Container maxWidth="xl" sx={{ py: 4 }}>
          <Box sx={{ mb: 4, textAlign: 'center' }}>
            <Box
              sx={{
                width: 80,
                height: 80,
                borderRadius: '50%',
                backgroundColor: 'rgba(249, 138, 60, 0.15)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                mx: 'auto',
                mb: 2,
              }}
            >
              <HomeIcon sx={{ color: BRAND.freedomOrange, fontSize: 40 }} />
            </Box>
            <Typography variant="h4" sx={{ color: '#fff', fontWeight: 600, mb: 1 }}>
              Link Hub
            </Typography>
            <Typography variant="body1" sx={{ color: '#999' }}>
              Quick access to dashboards and tools across the company
            </Typography>
          </Box>

          <Section title="PO Tool">
            {APP_VIEWS.map((link) => (
              <LinkCard key={link.url} {...link} />
            ))}
          </Section>

          <Section title="Dashboards">
            {DASHBOARDS.map((link) => (
              <LinkCard key={link.url} {...link} external />
            ))}
          </Section>

          <Section title="External Tools">
            {EXTERNAL_TOOLS.map((link) => (
              <LinkCard key={link.url} {...link} external accent={false} />
            ))}
          </Section>
        </Container>
      </Box>
    </ThemeProvider>
  );
}