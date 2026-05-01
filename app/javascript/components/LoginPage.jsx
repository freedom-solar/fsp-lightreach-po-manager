import React from 'react';
import { Box, Button, Container, Paper, Typography } from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

const theme = createTheme({
  palette: {
    primary: {
      main: '#1976d2',
    },
  },
});

const GoogleIcon = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
    <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
    <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
    <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
    <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
  </svg>
);

export default function LoginPage() {
  // Get logo URL from data attribute set by Rails asset pipeline
  const logoUrl = document.getElementById('react-root')?.getAttribute('data-logo-url');

  const handleGoogleLogin = () => {
    // Create a form and submit it as POST (required by Devise OmniAuth)
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = '/users/auth/google_oauth2';

    // Add CSRF token
    const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
    if (csrfToken) {
      const csrfInput = document.createElement('input');
      csrfInput.type = 'hidden';
      csrfInput.name = 'authenticity_token';
      csrfInput.value = csrfToken;
      form.appendChild(csrfInput);
    }

    document.body.appendChild(form);
    form.submit();
  };

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box
        sx={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          bgcolor: 'grey.100',
        }}
      >
        <Container maxWidth="sm">
          <Paper
            elevation={3}
            sx={{
              p: 4,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
            }}
          >
            <Box
              component="img"
              src={logoUrl}
              alt="Freedom Power"
              sx={{ width: 280, mb: 2 }}
            />
            <Typography variant="h5" component="h1" gutterBottom>
              Lightreach PO Manager
            </Typography>

            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }} align="center">
              Sign in with your @gofreedompower.com account to access the PO generation dashboard
            </Typography>

            <Button
              variant="contained"
              size="large"
              startIcon={<GoogleIcon />}
              onClick={handleGoogleLogin}
              sx={{
                mt: 2,
                bgcolor: '#4285f4',
                '&:hover': {
                  bgcolor: '#357abd',
                },
                textTransform: 'none',
                fontSize: '1rem',
                py: 1.5,
                px: 3,
              }}
            >
              Sign in with Google
            </Button>

            <Typography variant="body2" color="text.secondary" sx={{ mt: 3 }}>
              Use your Freedom Power email to sign in
            </Typography>
          </Paper>
        </Container>
      </Box>
    </ThemeProvider>
  );
}
