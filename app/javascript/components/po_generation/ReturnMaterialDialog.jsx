import React, { useState } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  TextField,
  Typography,
  Alert,
  CircularProgress,
  Box,
} from '@mui/material';

export default function ReturnMaterialDialog({ open, onClose, project, onSuccess }) {
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSubmit = async () => {
    if (!message.trim()) {
      setError('Please provide a reason for the material return');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/material_return/request', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({
          project_id: project.id,
          message: message.trim(),
        }),
      });

      const data = await response.json();

      if (data.success) {
        onSuccess && onSuccess(data);
        handleClose();
      } else {
        setError(data.error || 'Failed to submit material return request');
      }
    } catch (err) {
      setError('Network error: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    setMessage('');
    setError(null);
    onClose();
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ color: 'warning.main' }}>Request Material Return</DialogTitle>
      <DialogContent>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}

        <Box sx={{ mb: 2 }}>
          <Typography variant="body2" color="text.secondary">
            Project: <strong>{project?.name}</strong> ({project?.id})
          </Typography>
          {project?.po_link && (
            <Typography variant="body2" color="text.secondary">
              PO: <a href={project.po_link} target="_blank" rel="noopener noreferrer">View in NetSuite</a>
            </Typography>
          )}
        </Box>

        <TextField
          label="Reason for Return"
          placeholder="Please describe why materials need to be returned, including material status and whether all items are present..."
          multiline
          rows={4}
          fullWidth
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          disabled={loading}
          required
          sx={{ mt: 1 }}
        />

        <Typography variant="caption" color="text.secondary" sx={{ mt: 1, display: 'block' }}>
          This notification will be sent to the regional distribution list and you will be CC'd.
        </Typography>
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose} disabled={loading}>
          Cancel
        </Button>
        <Button
          onClick={handleSubmit}
          variant="contained"
          color="warning"
          disabled={loading || !message.trim()}
        >
          {loading ? <CircularProgress size={20} /> : 'Send Return Request'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
