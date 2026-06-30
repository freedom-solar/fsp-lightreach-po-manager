import React, { useState, useEffect, useMemo } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Container,
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
import { REGIONS, regionForLocation, isIgnoredLocation } from './regions';

const currency = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

const PendingChip = ({ pending }) =>
  pending ? (
    <Chip size="small" color="warning" label="Pending" variant="outlined" />
  ) : (
    <Chip size="small" color="success" label="Done" variant="outlined" />
  );

// Aging color buckets: <=30d green, 31-90d amber, >90d red.
const ageColor = (days) => {
  if (days == null) return 'default';
  if (days > 90) return 'error';
  if (days > 30) return 'warning';
  return 'success';
};

// Compact age label: days under a month, months under a year, then years (+ months).
const formatAge = (days) => {
  if (days < 30) return `${days}d`;

  const months = Math.round(days / 30);
  if (months < 12) return `${months}mo`;

  const years = Math.floor(months / 12);
  const remMonths = months % 12;
  return remMonths > 0 ? `${years}y ${remMonths}mo` : `${years}y`;
};

const AgeCell = ({ days, date }) => {
  if (days == null) {
    return (
      <Typography variant="body2" color="text.secondary">
        —
      </Typography>
    );
  }
  const chip = <Chip size="small" color={ageColor(days)} label={formatAge(days)} variant="outlined" />;
  const tooltip = [date && `PO date: ${date}`, `${days} days`].filter(Boolean).join(' · ');
  return <Tooltip title={tooltip}>{chip}</Tooltip>;
};

// Region tab selection is persisted to the URL (?clRegion=) so views are bookmarkable.
const REGION_PARAM = 'clRegion';

const getInitialRegion = () => {
  const r = new URLSearchParams(window.location.search).get(REGION_PARAM);
  return REGIONS.includes(r) ? r : 'All';
};

// Procurement dashboard: open Contract Labor POs split by region (NetSuite
// location) tabs, then grouped by Class, by vendor, with receipt/bill flagged
// separately. PO numbers deep-link to the NetSuite record.
export default function ProcurementDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [selectedRegion, setSelectedRegion] = useState(getInitialRegion);

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

  // Keep the selected region in the URL so the view can be bookmarked.
  useEffect(() => {
    const url = new URL(window.location);
    url.searchParams.set(REGION_PARAM, selectedRegion);
    window.history.replaceState({}, '', url);
  }, [selectedRegion]);

  const activeRegion = REGIONS.includes(selectedRegion) ? selectedRegion : 'All';

  // Apply the text filter and the active region, then group for display.
  const { groups, totalUnbilled, poCount } = useMemo(() => {
    const rows = data?.rows || [];
    const needle = search.trim().toLowerCase();

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
  }, [data, search, activeRegion]);

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
              Procurement — Open Contract Labor POs
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {poCount} open PO line group{poCount === 1 ? '' : 's'} ·{' '}
              {currency.format(totalUnbilled || 0)} unbilled ·{' '}
              {activeRegion === 'All' ? 'all regions' : activeRegion}
            </Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0 }}>
            <TextField
              size="small"
              label="Search"
              placeholder="vendor, PO, project…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              sx={{ width: 260, '& .MuiOutlinedInput-root': { height: 40 } }}
            />
            <Button
              variant="outlined"
              startIcon={<RefreshIcon />}
              onClick={fetchData}
              sx={{ height: 40 }}
            >
              Refresh
            </Button>
          </Box>
        </Box>

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
                    <TableCell align="center">Age</TableCell>
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
                    <TableRow
                      key={`${row.po_number}-${idx}`}
                      hover
                      onClick={
                        row.netsuite_url
                          ? () => window.open(row.netsuite_url, '_blank', 'noopener')
                          : undefined
                      }
                      sx={{ cursor: row.netsuite_url ? 'pointer' : 'default' }}
                    >
                      <TableCell>{row.vendor}</TableCell>
                      <TableCell sx={{ color: row.netsuite_url ? 'primary.main' : 'inherit' }}>
                        {row.po_number}
                      </TableCell>
                      <TableCell align="center">
                        <AgeCell days={row.age_days} date={row.po_date} />
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