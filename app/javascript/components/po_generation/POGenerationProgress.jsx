import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  LinearProgress,
  Typography,
  Alert,
  Button,
} from '@mui/material';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorIcon from '@mui/icons-material/Error';
import LogViewer from './LogViewer';
import { createConsumer } from '@rails/actioncable';

export default function POGenerationProgress({ jobId, onComplete }) {
  const [job, setJob] = useState(null);
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchJobStatus();

    // Set up ActionCable subscription for real-time updates
    const cable = createConsumer('/cable');
    const subscription = cable.subscriptions.create(
      { channel: 'PoGenerationChannel', job_id: jobId },
      {
        received(data) {
          if (data.type === 'status_update') {
            setJob((prev) => ({
              ...prev,
              status: data.status,
              successful_pos: data.successful_pos,
              failed_pos: data.failed_pos,
              completed_at: data.completed_at,
            }));

            if (data.status === 'completed' || data.status === 'failed') {
              onComplete?.();
            }
          } else {
            // Log message
            setLogs((prev) => [...prev, data]);
          }
        },
      }
    );

    return () => {
      subscription.unsubscribe();
      cable.disconnect();
    };
  }, [jobId]);

  const fetchJobStatus = async () => {
    try {
      const response = await fetch(`/api/v1/po_generation/jobs/${jobId}`);
      const data = await response.json();

      if (data.success) {
        setJob(data.data.job);
        setLogs(data.data.logs);
      }
    } catch (err) {
      console.error('Failed to fetch job status:', err);
    } finally {
      setLoading(false);
    }
  };

  const calculateProgress = () => {
    if (!job || !job.total_projects || job.total_projects === 0) return 0;
    const completed = (job.successful_pos || 0) + (job.failed_pos || 0);
    return (completed / job.total_projects) * 100;
  };

  const getStatusColor = () => {
    if (!job) return 'primary';
    switch (job.status) {
      case 'completed':
        return 'success';
      case 'failed':
        return 'error';
      case 'running':
        return 'primary';
      default:
        return 'default';
    }
  };

  const getStatusIcon = () => {
    if (!job) return null;
    if (job.status === 'completed') {
      return <CheckCircleIcon color="success" sx={{ mr: 1 }} />;
    }
    if (job.status === 'failed') {
      return <ErrorIcon color="error" sx={{ mr: 1 }} />;
    }
    return null;
  };

  if (loading) {
    return <LinearProgress />;
  }

  return (
    <Card>
      <CardContent>
        <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
          {getStatusIcon()}
          <Typography variant="h6">
            PO Generation Progress - Job #{jobId}
          </Typography>
        </Box>

        {job && (
          <>
            <Box mb={2}>
              <Typography variant="body2" color="text.secondary" gutterBottom>
                Status: {job.status.toUpperCase()}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Progress: {job.successful_pos || 0} successful, {job.failed_pos || 0} failed
                out of {job.total_projects} total
              </Typography>
            </Box>

            {job.status === 'running' && (
              <LinearProgress
                variant="determinate"
                value={calculateProgress()}
                color={getStatusColor()}
                sx={{ mb: 2, height: 8, borderRadius: 1 }}
              />
            )}

            {job.error_message && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {job.error_message}
              </Alert>
            )}

            {(job.status === 'completed' || job.status === 'failed') && (
              <Alert
                severity={job.status === 'completed' ? 'success' : 'error'}
                sx={{ mb: 2 }}
              >
                {job.status === 'completed'
                  ? `Successfully generated ${job.successful_pos} PO(s)`
                  : `Job failed: ${job.error_message || 'Unknown error'}`}
              </Alert>
            )}
          </>
        )}

        <LogViewer logs={logs} />

        {job?.status === 'completed' && (
          <Box sx={{ mt: 2, display: 'flex', justifyContent: 'flex-end' }}>
            <Button variant="outlined" onClick={onComplete}>
              Back to Dashboard
            </Button>
          </Box>
        )}
      </CardContent>
    </Card>
  );
}
