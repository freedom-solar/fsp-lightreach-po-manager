import React, { useState, useEffect, useMemo } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Container,
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
import { REGIONS, regionForLocation, isIgnoredLocation } from './regions';

const formatDate = (iso) => {
  if (!iso) return null;
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};

const daysUntil = (iso) => {
  if (!iso) return null;
  const [y, m, d] = iso.split('-').map(Number);
  const target = new Date(y, m - 1, d);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Math.round((target - today) / 86400000);
};

// Project-level schedule urgency chip (overdue / at-risk vs the install date).
const ScheduleChip = ({ urgency, installDate }) => {
  if (!urgency || !installDate) return null;
  const days = daysUntil(installDate);
  if (urgency === 'overdue') {
    return <Chip size="small" color="error" label={`Overdue ${Math.abs(days)}d`} />;
  }
  return <Chip size="small" color="warning" label={days <= 0 ? 'Due today' : `Due in ${days}d`} />;
};

const QtyCell = ({ value, color }) => (
  <TableCell align="right" sx={value > 0 ? { color: `${color}.main`, fontWeight: 600 } : undefined}>
    {value}
  </TableCell>
);

// Inventory dashboard (Warehouse Managers): open inventory POs split by region,
// grouped by project, showing what's not received and received-but-not-allocated,
// with late fulfillments flagged against the Skedulo install schedule.
export default function InventoryDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [selectedRegion, setSelectedRegion] = useState('All');

  const fetchData = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/inventory/open_items');
      const json = await response.json();

      if (json.success) {
        setData(json.data);
      } else {
        setError(json.error || 'Failed to load inventory dashboard');
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

  // Filter by region + search, then group by project.
  const { groups, itemCount, lateCount } = useMemo(() => {
    const rows = data?.rows || [];
    const needle = search.trim().toLowerCase();

    const filtered = rows.filter((row) => {
      if (isIgnoredLocation(row.location)) return false;
      if (activeRegion !== 'All' && regionForLocation(row.location) !== activeRegion) return false;
      if (!needle) return true;
      return [row.project, row.project_number, row.item, row.location, ...(row.po_numbers || [])]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(needle));
    });

    const byProject = new Map();
    filtered.forEach((row) => {
      const key = `${row.project}__${row.location}`;
      if (!byProject.has(key)) {
        byProject.set(key, {
          key,
          project: row.project,
          project_number: row.project_number,
          location: row.location,
          install_date: row.install_date,
          region: row.region,
          urgency: row.urgency,
          rows: [],
        });
      }
      byProject.get(key).rows.push(row);
    });

    const rank = (u) => ({ overdue: 0, at_risk: 1 }[u] ?? 2);
    const groupList = Array.from(byProject.values()).sort(
      (a, b) =>
        rank(a.urgency) - rank(b.urgency) ||
        a.location.localeCompare(b.location) ||
        a.project.localeCompare(b.project)
    );

    return {
      groups: groupList,
      itemCount: filtered.length,
      lateCount: filtered.filter((r) => r.late).length,
    };
  }, [data, search, activeRegion]);

  if (loading) {
    return (
      <Container maxWidth="xl" sx={{ flexGrow: 1, py: 6, textAlign: 'center' }}>
        <CircularProgress color="primary" />
        <Typography sx={{ mt: 2 }} color="text.secondary">
          Loading open inventory POs from NetSuite…
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
              Inventory — Open POs by Project
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {itemCount} item{itemCount === 1 ? '' : 's'} across {groups.length} project
              {groups.length === 1 ? '' : 's'} · {lateCount} late ·{' '}
              {activeRegion === 'All' ? 'all regions' : activeRegion}
            </Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexShrink: 0 }}>
            <TextField
              size="small"
              label="Search"
              placeholder="project, item, PO…"
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

        {!error && groups.length === 0 && (
          <Alert severity="info">No open inventory POs match the current filter.</Alert>
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
                gap: 2,
                flexWrap: 'wrap',
              }}
            >
              <Box>
                <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                  {group.project}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  {group.location}
                  {group.install_date ? ` · install ${formatDate(group.install_date)}` : ' · not scheduled'}
                </Typography>
              </Box>
              <ScheduleChip urgency={group.urgency} installDate={group.install_date} />
            </Box>
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Item</TableCell>
                    <TableCell align="right">Ordered</TableCell>
                    <TableCell align="right">Received</TableCell>
                    <TableCell align="right">Allocated</TableCell>
                    <TableCell align="right">Not Received</TableCell>
                    <TableCell align="right">In Warehouse</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {group.rows.map((row, idx) => (
                    <TableRow key={`${row.item}-${idx}`} hover>
                      <TableCell>{row.item}</TableCell>
                      <TableCell align="right">{row.ordered_qty}</TableCell>
                      <TableCell align="right">{row.received_qty}</TableCell>
                      <TableCell align="right">{row.allocated_qty}</TableCell>
                      <QtyCell value={row.not_received_qty} color="warning" />
                      <QtyCell value={row.received_not_allocated_qty} color="info" />
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