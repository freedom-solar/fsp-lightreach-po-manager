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

const PendingChip = ({ pending, label }) =>
  pending ? (
    <Chip size="small" color="warning" label={label} variant="outlined" />
  ) : (
    <Chip size="small" color="success" label="Done" variant="outlined" />
  );

// Procurement dashboard: open Contract Labor POs grouped by NetSuite
// Class + Location, by vendor, with pending receipt/bill flagged separately.
export default function ProcurementDashboard() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState('');

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

  // Filter rows, then group by "Class • Location".
  const groups = useMemo(() => {
    const rows = data?.rows || [];
    const needle = filter.trim().toLowerCase();

    const filtered = needle
      ? rows.filter((r) =>
          [r.vendor, r.ns_class, r.location, r.po_number, ...(r.projects || [])]
            .filter(Boolean)
            .some((v) => String(v).toLowerCase().includes(needle))
        )
      : rows;

    const byGroup = new Map();
    filtered.forEach((row) => {
      const key = `${row.ns_class} • ${row.location}`;
      if (!byGroup.has(key)) byGroup.set(key, []);
      byGroup.get(key).push(row);
    });

    return Array.from(byGroup.entries()).map(([key, groupRows]) => ({
      key,
      rows: groupRows,
      unbilled: groupRows.reduce((sum, r) => sum + (r.unbilled_amount || 0), 0),
    }));
  }, [data, filter]);

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
          {data && (
            <Typography variant="body2" color="text.secondary">
              {data.count} open PO line group{data.count === 1 ? '' : 's'} ·{' '}
              {currency.format(data.total_unbilled_amount || 0)} unbilled ·
              {' '}grouped by Class • Location, by vendor
            </Typography>
          )}
        </Box>
        <Stack direction="row" spacing={2} alignItems="center">
          <TextField
            size="small"
            label="Filter"
            placeholder="vendor, PO, project…"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
          <Button
            variant="outlined"
            startIcon={<RefreshIcon />}
            onClick={fetchData}
          >
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
                  <TableCell align="center">Pending Receipt</TableCell>
                  <TableCell align="center">Pending Bill</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {group.rows.map((row, idx) => (
                  <TableRow key={`${row.po_number}-${idx}`} hover>
                    <TableCell>{row.vendor}</TableCell>
                    <TableCell>{row.po_number}</TableCell>
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
                      <PendingChip pending={row.pending_receipt} label="Pending" />
                    </TableCell>
                    <TableCell align="center">
                      <PendingChip pending={row.pending_bill} label="Pending" />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      ))}
    </Container>
  );
}