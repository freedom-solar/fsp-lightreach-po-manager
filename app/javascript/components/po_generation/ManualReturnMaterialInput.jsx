import React, { useState } from 'react';
import {
  Box,
  TextField,
  Button,
  Typography,
  Alert,
  CircularProgress,
} from '@mui/material';
import AssignmentReturnIcon from '@mui/icons-material/AssignmentReturn';

export default function ManualReturnMaterialInput({ onReturnMaterial }) {
  const [projectId, setProjectId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!projectId.trim()) return;

    setLoading(true);
    setError(null);

    try {
      // Fetch project details first to verify it exists and has a PO
      const response = await fetch(`/api/v1/projects/${projectId.trim()}`);
      const data = await response.json();

      if (!data.success) {
        setError(data.error || 'Project not found');
        return;
      }

      const project = data.data.project;

      if (!project.has_po) {
        setError('This project does not have a PO. Only projects with existing POs can request material returns.');
        return;
      }

      // Open the return material dialog
      onReturnMaterial(project);
      setProjectId('');
    } catch (err) {
      setError('Network error: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box>
      <Typography variant="h6" gutterBottom>
        Manual Material Return Request
      </Typography>
      <Typography variant="body2" color="text.secondary" gutterBottom>
        Enter a Project Sunrise ID to request a material return for a project not shown above
      </Typography>

      {error && (
        <Alert severity="error" sx={{ mt: 2, mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      <Box component="form" onSubmit={handleSubmit} sx={{ mt: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-start' }}>
          <TextField
            label="Project ID"
            placeholder="e.g., proj_abc123"
            value={projectId}
            onChange={(e) => setProjectId(e.target.value)}
            size="small"
            sx={{ flex: 1 }}
            disabled={loading}
          />
          <Button
            type="submit"
            variant="contained"
            color="warning"
            startIcon={loading ? <CircularProgress size={20} /> : <AssignmentReturnIcon />}
            disabled={!projectId.trim() || loading}
          >
            Request Return
          </Button>
        </Box>
      </Box>
    </Box>
  );
}
