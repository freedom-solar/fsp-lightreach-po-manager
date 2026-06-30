import React, { useState, useEffect, useMemo } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Container,
  Link,
  Paper,
  Tab,
  Tabs,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import BoltIcon from '@mui/icons-material/Bolt';
import { REGIONS, regionForLocation, isIgnoredLocation } from './regions';

const REGION_PARAM = 'mfRegion';

const getInitialRegion = () => {
  const r = new URLSearchParams(window.location.search).get(REGION_PARAM);
  return REGIONS.includes(r) ? r : 'All';
};

const formatDate = (iso) => {
  if (!iso) return '—';
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
};

// Missed Fulfillments: Sales Orders pending/partially fulfilled whose governing
// scheduled date (electrical for energy-storage SOs, else installation) is past.
export default function MissedFulfillments() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [selectedRegion, setSelectedRegion] = useState(getInitialRegion);

  const fetchData = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/missed_fulfillments');
      const json = await response.json();

      if (json.success) {
        setData(json.data);
      } else {
        setError(json.error || 'Failed to load missed fulfillments');
      }
    } catch (err) {
      setError('Network error: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  useEffect(() => {
    const url = new URL(window.location);
    url.searchParams.set(REGION_PARAM, selectedRegion);
    window.history.replaceState({}, '', url);
  }, [selectedRegion]);

  const activeRegion = REGIONS.includes(selectedRegion) ? selectedRegion : 'All';

  const rows = useMemo(() => {
    const all = data?.rows || [];
    const needle = search.trim().toLowerCase();

    return all.filter((row) => {
      if (isIgnoredLocation(row.location)) return false;
      if (activeRegion !== 'All' && regionForLocation(row.location) !== activeRegion) return false;
      if (!needle) return true;
      return [row.project_number, row.customer, row.location, row.status_label]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(needle));
    });
  }, [data, search, activeRegion]);

  if (loading) {
    return (
      <Container maxWidth="xl" sx={{ flexGrow: 1, py: 6, textAlign: 'center' }}>
        <CircularProgress color="primary" />
        <Typography sx={{ mt: 2 }} color="text.secondary">
          Loading missed fulfillments from NetSuite…
        </Typography>
      </Container>
    );
  }

  return (
    <>
      {data && (
        <Box sx={{ borderBottom: 1, borderColor: 'divider', bgcolor: 'background.paper' }}>
          <Container maxWidth="xl">
            <Tabs
              value={activeRegion}
              onChange={(e, value) => setSelectedRegion(value)}
              aria-label="region tabs"
              variant="scrollable"
              scrollButtons="auto"
            >
              {REGIONS.map((region) => (
                <Tab key={region} label={region} value={region} />
              ))}
            </Tabs>
          </Container>
        </Box>
      )}

      <Container maxWidth="xl" sx={{ flexGrow: 1, py: 3 }}>
        <Box
          sx={{
            display: 'flex',
            flexDirection: { xs: 'column', sm: 'row' },
            justifyContent: 'space-between',
            alignItems: { sm: 'center' },
            gap: 2,
            mb: 3,
          }}
        >
          <Box>
            <Typography variant="h5" sx={{ fontWeight: 600 }}>
              Missed Fulfillments
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {rows.length} sales order{rows.length === 1 ? '' : 's'} past their scheduled date ·{' '}
              {activeRegion === 'All' ? 'all regions' : activeRegion}
            </Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0 }}>
            <TextField
              size="small"
              label="Search"
              placeholder="project, customer…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              sx={{ width: 260, '& .MuiOutlinedInput-root': { height: 40 } }}
            />
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={fetchData} sx={{ height: 40 }}>
              Refresh
            </Button>
          </Box>
        </Box>

        {error && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}

        {!error && rows.length === 0 && (
          <Alert severity="success">No missed fulfillments for the current filter. 🎉</Alert>
        )}

        {rows.length > 0 && (
          <Paper variant="outlined" sx={{ overflow: 'hidden' }}>
            <TableContainer>
              <Table size="small" stickyHeader>
                <TableHead>
                  <TableRow>
                    <TableCell>Project</TableCell>
                    <TableCell>Customer</TableCell>
                    <TableCell>Location</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Installation</TableCell>
                    <TableCell>Electrical</TableCell>
                    <TableCell align="right">Overdue</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {rows.map((row, idx) => (
                    <TableRow key={`${row.project_number}-${idx}`} hover>
                      <TableCell>
                        {row.netsuite_url ? (
                          <Link href={row.netsuite_url} target="_blank" rel="noopener" underline="hover">
                            {row.project_number}
                          </Link>
                        ) : (
                          row.project_number
                        )}
                      </TableCell>
                      <TableCell>{row.customer}</TableCell>
                      <TableCell>{row.location}</TableCell>
                      <TableCell>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                          <Typography variant="body2">{row.status_label}</Typography>
                          {row.has_storage && (
                            <Tooltip title="Has Energy Storage Components — governed by the electrical date">
                              <BoltIcon sx={{ fontSize: 16, color: 'warning.main' }} />
                            </Tooltip>
                          )}
                        </Box>
                      </TableCell>
                      <TableCell sx={row.governing_basis === 'installation' ? { fontWeight: 700 } : { color: 'text.secondary' }}>
                        {formatDate(row.installation_date)}
                      </TableCell>
                      <TableCell sx={row.governing_basis === 'electrical' ? { fontWeight: 700 } : { color: 'text.secondary' }}>
                        {formatDate(row.electrical_date)}
                      </TableCell>
                      <TableCell align="right">
                        <Chip
                          size="small"
                          color={row.days_overdue > 30 ? 'error' : 'warning'}
                          label={`${row.days_overdue}d`}
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </Paper>
        )}
      </Container>
    </>
  );
}
