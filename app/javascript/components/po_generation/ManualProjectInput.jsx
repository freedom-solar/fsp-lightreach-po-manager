import React, { useState } from 'react';
import {
  Box,
  TextField,
  Button,
  Typography,
  FormControlLabel,
  Checkbox,
} from '@mui/material';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';

export default function ManualProjectInput({ onGenerate }) {
  const [projectId, setProjectId] = useState('');
  const [skipEmail, setSkipEmail] = useState(false);
  const [skipCrewCheck, setSkipCrewCheck] = useState(false);

  const handleSubmit = (e) => {
    e.preventDefault();
    if (projectId.trim()) {
      onGenerate(projectId.trim(), { skipEmail, skipCrewCheck });
      setProjectId('');
    }
  };

  return (
    <Box>
      <Typography variant="h6" gutterBottom>
        Generate PO for Manual Project
      </Typography>
      <Typography variant="body2" color="text.secondary" gutterBottom>
        Enter a Project Sunrise ID to generate a PO for a project not currently on schedule
      </Typography>

      <Box component="form" onSubmit={handleSubmit} sx={{ mt: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-start', mb: 3 }}>
          <TextField
            label="Project ID"
            placeholder="e.g., proj_abc123"
            value={projectId}
            onChange={(e) => setProjectId(e.target.value)}
            size="small"
            sx={{ flex: 1 }}
          />
          <Button
            type="submit"
            variant="contained"
            startIcon={<PlayArrowIcon />}
            disabled={!projectId.trim()}
            sx={{ ml: 2 }}
          >
            Generate PO
          </Button>
        </Box>

        <Box sx={{ mt: 2, pt: 2, borderTop: '1px solid', borderColor: 'divider' }}>
          <Typography variant="subtitle2" gutterBottom sx={{ fontWeight: 600 }}>
            Options (for manual project only):
          </Typography>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <FormControlLabel
              control={
                <Checkbox
                  checked={skipEmail}
                  onChange={(e) => setSkipEmail(e.target.checked)}
                  size="small"
                />
              }
              label="Skip email notification to CED (just generate PO in Netsuite)"
            />
            <FormControlLabel
              control={
                <Checkbox
                  checked={skipCrewCheck}
                  onChange={(e) => setSkipCrewCheck(e.target.checked)}
                  size="small"
                />
              }
              label="Send PO even if Crew Install already complete"
            />
          </Box>
        </Box>
      </Box>
    </Box>
  );
}
