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
  const [selectedProjects, setSelectedProjects] = useState([]);
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
        const fetchedProjects = data.data.projects;
        setProjects(fetchedProjects);
        // Select all projects by default
        setSelectedProjects(fetchedProjects.map(p => p.id));
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
    if (selectedProjects.length === 0) {
      alert('Please select at least one project');
      return;
    }

    if (!confirm(`Generate POs for ${selectedProjects.length} selected project(s) in ${region}?`)) {
      return;
    }

    try {
      const response = await fetch('/api/v1/po_generation/batch', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({ project_ids: selectedProjects }),
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

  const handleToggleProject = (projectId) => {
    setSelectedProjects(prev =>
      prev.includes(projectId)
        ? prev.filter(id => id !== projectId)
        : [...prev, projectId]
    );
  };

  const handleToggleAll = (projectIds) => {
    if (selectedProjects.length === projectIds.length) {
      setSelectedProjects([]);
    } else {
      setSelectedProjects(projectIds);
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
              {region} - {projects.length} Projects on Schedule ({selectedProjects.length} selected)
            </Typography>
            <Button
              variant="contained"
              color="primary"
              startIcon={<PlayArrowIcon />}
              onClick={handleGenerateRegion}
              disabled={selectedProjects.length === 0}
            >
              GENERATE ALL POS FOR {region.toUpperCase()} & SEND TO CED
            </Button>
          </Box>

          <ProjectList
            projects={projects}
            selectedProjects={selectedProjects}
            onToggleProject={handleToggleProject}
            onToggleAll={handleToggleAll}
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
