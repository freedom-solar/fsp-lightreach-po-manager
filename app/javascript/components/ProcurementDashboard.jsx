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
  Stack,
  Tab,
  Tabs,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';

const currency = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

// Fixed Procurement region tabs. NetSuite locations roll up into these
// (San Antonio is part of Austin; Dallas shows as DFW).
const REGIONS = ['All', 'Commercial', 'Austin', 'DFW', 'Houston', 'Orlando', 'Tampa'];

const LOCATION_TO_REGION = {
  Commercial: 'Commercial',
  Austin: 'Austin',
  'San Antonio': 'Austin',
  Dallas: 'DFW',
  Houston: 'Houston',
  Orlando: 'Orlando',
  Tampa: 'Tampa',
};

// Maps a NetSuite location (incl. "X - Consignment" variants) to a region tab,
// or null if it isn't part of one of the fixed regions (shown only under "All").
const regionForLocation = (location) => {
  if (!location) return null;
  const base = location.replace(/\s*-\s*Consignment$/i, '').trim();
  return LOCATION_TO_REGION[base] || null;
};

// Locations excluded from the dashboard entirely (even under "All").
const IGNORED_LOCATIONS = ['Charlotte'];

const isIgnoredLocation = (location) => {
  if (!location) return false;
  const base = location.replace(/\s*-\s*Consignment$/i, '').trim();
  return IGNORED_LOCATIONS.includes(base);
};

const PendingChip = ({ pending }) =>
  pending ? (
    <Chip size="small" color="warning" label="Pending" variant="outlined" />
  ) : (
    <Chip size="small" color="success" label="Done" variant="outlined" />
  );

// Procurement dashboard: open Contract Labor POs split by region (NetSuite
// location) tabs, then grouped by Class, by vendor, with receipt/bill flagged
// separately. PO numbers deep-link to the NetSuite record.
export default function ProcurementDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState('');
  const [selectedRegion, setSelectedRegion] = useState('All');

  const fetchData = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/procurement/open_pos');
      const json = await response.json();

      if (json.success) {
        setData(json.data);
      } else {
        setError(json.error || 'Failed to load procurement dashboard');
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

  const activeRegion = REGIONS.includes(selectedRegion) ? selectedRegion : 'All';

  // Apply the text filter and the active region, then group for display.
  const { groups, totalUnbilled, poCount } = useMemo(() => {
    const rows = data?.rows || [];
    const needle = filter.trim().toLowerCase();

    const filtered = rows.filter((row) => {
      if (isIgnoredLocation(row.location)) return false;
      if (activeRegion !== 'All' && regionForLocation(row.location) !== activeRegion) return false;
      if (!needle) return true;
      return [row.vendor, row.ns_class, row.location, row.po_number, ...(row.projects || [])]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(needle));
    });

    const byGroup = new Map();
    filtered.forEach((row) => {
      // Within a region the location is fixed, so group by class only.
      const key = activeRegion === 'All' ? `${row.ns_class} • ${row.location}` : row.ns_class;
      if (!byGroup.has(key)) byGroup.set(key, []);
      byGroup.get(key).push(row);
    });

    return {
      groups: Array.from(byGroup.entries()).map(([key, groupRows]) => ({
        key,
        rows: groupRows,
        unbilled: groupRows.reduce((sum, r) => sum + (r.unbilled_amount || 0), 0),
      })),
      totalUnbilled: filtered.reduce((sum, r) => sum + (r.unbilled_amount || 0), 0),
      poCount: filtered.length,
    };
  }, [data, filter, activeRegion]);

  if (loading) {
    return (
      <Container maxWidth="xl" sx={{ flexGrow: 1, py: 6, textAlign: 'center' }}>
        <CircularProgress color="primary" />
        <Typography sx={{ mt: 2 }} color="text.secondary">
          Loading open Contract Labor POs from NetSuite…
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
        <Stack
          direction={{ xs: 'column', sm: 'row' }}
          spacing={2}
          alignItems={{ sm: 'center' }}
          justifyContent="space-between"
          sx={{ mb: 3 }}
        >
          <Box>
            <Typography variant="h5" sx={{ fontWeight: 600 }}>
              Procurement — Open Contract Labor POs
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {poCount} open PO line group{poCount === 1 ? '' : 's'} ·{' '}
              {currency.format(totalUnbilled || 0)} unbilled ·{' '}
              {activeRegion === 'All' ? 'all regions' : activeRegion}
            </Typography>
          </Box>
          <Stack direction="row" spacing={2} alignItems="center">
            <TextField
              size="small"
              label="Filter"
              placeholder="vendor, PO, project…"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            />
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={fetchData}>
              Refresh
            </Button>
          </Stack>
        </Stack>

        {error && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}

        {!error && groups.length === 0 && (
          <Alert severity="info">No open Contract Labor POs match the current filter.</Alert>
        )}

        {groups.map((group) => (
          <Paper key={group.key} variant="outlined" sx={{ mb: 3, overflow: 'hidden' }}>
            <Box
              sx={{
                px: 2,
                py: 1.5,
                bgcolor: 'background.default',
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
              }}
            >
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                {group.key}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                {group.rows.length} PO{group.rows.length === 1 ? '' : 's'} ·{' '}
                {currency.format(group.unbilled)} unbilled
              </Typography>
            </Box>
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Vendor</TableCell>
                    <TableCell>PO #</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell align="right">Ordered</TableCell>
                    <TableCell align="right">Received</TableCell>
                    <TableCell align="right">Billed</TableCell>
                    <TableCell align="right">Unbilled $</TableCell>
                    <TableCell align="center">Receipt</TableCell>
                    <TableCell align="center">Bill</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {group.rows.map((row, idx) => (
                    <TableRow key={`${row.po_number}-${idx}`} hover>
                      <TableCell>{row.vendor}</TableCell>
                      <TableCell>
                        {row.netsuite_url ? (
                          <Link
                            href={row.netsuite_url}
                            target="_blank"
                            rel="noopener"
                            underline="hover"
                          >
                            {row.po_number}
                          </Link>
                        ) : (
                          row.po_number
                        )}
                      </TableCell>
                      <TableCell>
                        <Typography variant="body2">{row.status_label}</Typography>
                        {row.projects && row.projects.length > 0 && (
                          <Typography variant="caption" color="text.secondary">
                            {row.projects.join(', ')}
                          </Typography>
                        )}
                      </TableCell>
                      <TableCell align="right">{row.ordered_qty}</TableCell>
                      <TableCell align="right">{row.received_qty}</TableCell>
                      <TableCell align="right">{row.billed_qty}</TableCell>
                      <TableCell align="right">{currency.format(row.unbilled_amount || 0)}</TableCell>
                      <TableCell align="center">
                        <PendingChip pending={row.pending_receipt} />
                      </TableCell>
                      <TableCell align="center">
                        <PendingChip pending={row.pending_bill} />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </Paper>
        ))}
      </Container>
    </>
  );
}