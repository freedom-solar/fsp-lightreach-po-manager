import React, { useState, useEffect } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  Alert,
  Typography,
  Paper,
} from '@mui/material';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import ProjectList from './ProjectList';
import POGenerationProgress from './POGenerationProgress';
import ManualProjectInput from './ManualProjectInput';

export default function RegionView({ region }) {
  const [projects, setProjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeJobId, setActiveJobId] = useState(null);

  useEffect(() => {
    fetchProjects();
  }, [region]);

  const fetchProjects = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`/api/v1/projects/schedule/${region}`);
      const data = await response.json();

      if (data.success) {
        setProjects(data.data.projects);
      } else {
        setError(data.error || 'Failed to fetch projects');
      }
    } catch (err) {
      setError('Network error: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateRegion = async () => {
    if (!confirm(`Generate POs for all ${projects.length} projects in ${region}?`)) {
      return;
    }

    try {
      const response = await fetch('/api/v1/po_generation/region', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({ region }),
      });

      const data = await response.json();

      if (data.success) {
        setActiveJobId(data.data.job_id);
      } else {
        setError(data.error || 'Failed to start PO generation');
      }
    } catch (err) {
      setError('Network error: ' + err.message);
    }
  };

  const handleGenerateSingle = async (projectId) => {
    try {
      const response = await fetch('/api/v1/po_generation/project', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({ project_id: projectId }),
      });

      const data = await response.json();

      if (data.success) {
        setActiveJobId(data.data.job_id);
      } else {
        setError(data.error || 'Failed to start PO generation');
      }
    } catch (err) {
      setError('Network error: ' + err.message);
    }
  };

  const handleJobComplete = () => {
    setActiveJobId(null);
    fetchProjects(); // Refresh project list
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  return (
    <Box>
      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
          {error}
        </Alert>
      )}

      {activeJobId ? (
        <POGenerationProgress
          jobId={activeJobId}
          onComplete={handleJobComplete}
        />
      ) : (
        <>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3, gap: 3 }}>
            <Typography variant="h5">
              {region} - {projects.length} Projects on Schedule
            </Typography>
            <Button
              variant="contained"
              color="primary"
              startIcon={<PlayArrowIcon />}
              onClick={handleGenerateRegion}
              disabled={projects.length === 0}
            >
              Generate All POs for {region}
            </Button>
          </Box>

          <ProjectList
            projects={projects}
            onGenerateSingle={handleGenerateSingle}
          />

          <Paper sx={{ mt: 3, p: 3 }}>
            <ManualProjectInput onGenerate={handleGenerateSingle} />
          </Paper>
        </>
      )}
    </Box>
  );
}
