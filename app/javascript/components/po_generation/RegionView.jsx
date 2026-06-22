import React, { useState, useEffect } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  Alert,
  Typography,
  Paper,
  Snackbar,
  ToggleButton,
  ToggleButtonGroup,
} from '@mui/material';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import ProjectList from './ProjectList';
import POGenerationProgress from './POGenerationProgress';
import ManualProjectInput from './ManualProjectInput';
import ReturnMaterialDialog from './ReturnMaterialDialog';
import ManualReturnMaterialInput from './ManualReturnMaterialInput';

export default function RegionView({ region }) {
  const [projects, setProjects] = useState([]);
  const [selectedProjects, setSelectedProjects] = useState([]);
  const [programFilter, setProgramFilter] = useState('all');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeJobId, setActiveJobId] = useState(null);
  const [returnDialogOpen, setReturnDialogOpen] = useState(false);
  const [returnProject, setReturnProject] = useState(null);
  const [successMessage, setSuccessMessage] = useState(null);

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
        // Reset to the unfiltered view and select all projects by default
        setProgramFilter('all');
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

  const handleProgramFilterChange = (event, newFilter) => {
    // ToggleButtonGroup passes null when the active button is re-clicked; ignore it.
    if (newFilter === null) return;
    setProgramFilter(newFilter);
    // Keep the selection in sync with what's visible so "Generate All" only acts on
    // the filtered program.
    const visible = newFilter === 'all'
      ? projects
      : projects.filter(p => p.program_type === newFilter);
    setSelectedProjects(visible.map(p => p.id));
  };

  const handleGenerateSingle = async (projectId, options = {}) => {
    const { skipEmail = false } = options;

    try {
      const response = await fetch('/api/v1/po_generation/project', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        },
        body: JSON.stringify({
          project_id: projectId,
          skip_email: skipEmail
        }),
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

  const handleReturnMaterial = (project) => {
    setReturnProject(project);
    setReturnDialogOpen(true);
  };

  const handleReturnSuccess = () => {
    setSuccessMessage('Material return request sent successfully');
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
        <CircularProgress />
      </Box>
    );
  }

  const directPayCount = projects.filter(p => p.program_type === 'direct_pay').length;
  const cedKittedCount = projects.filter(p => p.program_type === 'ced_kitted').length;
  const visibleProjects = programFilter === 'all'
    ? projects
    : projects.filter(p => p.program_type === programFilter);

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
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1, gap: 3 }}>
            <Box>
              <Typography variant="h5">
                {region} - {projects.length} Projects on Schedule ({selectedProjects.length} selected)
              </Typography>
              <Typography variant="body2" color="text.secondary">
                {directPayCount} Lightreach Direct Pay · {cedKittedCount} CED Kitted Job
              </Typography>
            </Box>
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

          <ToggleButtonGroup
            value={programFilter}
            exclusive
            onChange={handleProgramFilterChange}
            size="small"
            sx={{ mb: 2 }}
          >
            <ToggleButton value="all">All ({projects.length})</ToggleButton>
            <ToggleButton value="direct_pay">Lightreach Direct Pay ({directPayCount})</ToggleButton>
            <ToggleButton value="ced_kitted">CED Kitted Job ({cedKittedCount})</ToggleButton>
          </ToggleButtonGroup>

          <ProjectList
            projects={visibleProjects}
            selectedProjects={selectedProjects}
            onToggleProject={handleToggleProject}
            onToggleAll={handleToggleAll}
            onGenerateSingle={handleGenerateSingle}
            onReturnMaterial={handleReturnMaterial}
          />

          <Paper sx={{ mt: 3, p: 3 }}>
            <ManualProjectInput onGenerate={handleGenerateSingle} />
          </Paper>

          <Paper sx={{ mt: 3, p: 3 }}>
            <ManualReturnMaterialInput onReturnMaterial={handleReturnMaterial} />
          </Paper>
        </>
      )}

      <ReturnMaterialDialog
        open={returnDialogOpen}
        onClose={() => setReturnDialogOpen(false)}
        project={returnProject}
        onSuccess={handleReturnSuccess}
      />

      <Snackbar
        open={!!successMessage}
        autoHideDuration={6000}
        onClose={() => setSuccessMessage(null)}
        message={successMessage}
      />
    </Box>
  );
}
