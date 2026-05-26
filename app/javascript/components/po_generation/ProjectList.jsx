import React, { useState } from 'react';
import {
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Button,
  ButtonGroup,
  Chip,
  Link,
  Box,
  Checkbox,
  Menu,
  MenuItem,
  ListItemIcon,
  ListItemText,
} from '@mui/material';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import ArrowDropDownIcon from '@mui/icons-material/ArrowDropDown';
import EmailIcon from '@mui/icons-material/Email';
import DescriptionIcon from '@mui/icons-material/Description';
import AssignmentReturnIcon from '@mui/icons-material/AssignmentReturn';

function ProjectActionButton({ project, onGenerateSingle, onReturnMaterial }) {
  const [anchorEl, setAnchorEl] = useState(null);
  const open = Boolean(anchorEl);

  const handleClick = (event) => {
    setAnchorEl(event.currentTarget);
  };

  const handleClose = () => {
    setAnchorEl(null);
  };

  const handleGenerateAndSend = () => {
    onGenerateSingle(project.id, { skipEmail: false });
    handleClose();
  };

  const handleGenerateOnly = () => {
    onGenerateSingle(project.id, { skipEmail: true });
    handleClose();
  };

  const handleReturnMaterial = () => {
    onReturnMaterial(project);
    handleClose();
  };

  // For projects that already have a PO, show two separate buttons
  if (project.has_po) {
    return (
      <Box sx={{ display: 'flex', gap: 2, justifyContent: 'flex-end' }}>
        <Button
          size="small"
          variant="outlined"
          startIcon={<PlayArrowIcon />}
          onClick={() => onGenerateSingle(project.id, { skipEmail: false })}
        >
          Send PO to CED
        </Button>
        <Button
          size="small"
          variant="outlined"
          color="warning"
          startIcon={<AssignmentReturnIcon />}
          onClick={() => onReturnMaterial(project)}
        >
          Return Material
        </Button>
      </Box>
    );
  }

  // For projects without a PO, show split button with options
  return (
    <>
      <ButtonGroup variant="outlined" size="small">
        <Button
          startIcon={<PlayArrowIcon />}
          onClick={handleGenerateAndSend}
        >
          Generate PO & Send to CED
        </Button>
        <Button
          size="small"
          onClick={handleClick}
        >
          <ArrowDropDownIcon />
        </Button>
      </ButtonGroup>
      <Menu
        anchorEl={anchorEl}
        open={open}
        onClose={handleClose}
      >
        <MenuItem onClick={handleGenerateAndSend}>
          <ListItemIcon>
            <EmailIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText>Generate PO & Send to CED</ListItemText>
        </MenuItem>
        <MenuItem onClick={handleGenerateOnly}>
          <ListItemIcon>
            <DescriptionIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText>Generate PO Only (No Email)</ListItemText>
        </MenuItem>
      </Menu>
    </>
  );
}

export default function ProjectList({ projects, onGenerateSingle, selectedProjects, onToggleProject, onToggleAll, onReturnMaterial }) {
  const formatDate = (dateString) => {
    if (!dateString) return 'N/A';
    return new Date(dateString).toLocaleDateString();
  };

  if (projects.length === 0) {
    return (
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <p>No projects scheduled for this region.</p>
      </Paper>
    );
  }

  // Sort projects by job_start date ascending
  const sortedProjects = [...projects].sort((a, b) => {
    if (!a.job_start) return 1;
    if (!b.job_start) return -1;
    return new Date(a.job_start) - new Date(b.job_start);
  });

  const allSelected = sortedProjects.length > 0 && sortedProjects.every(p => selectedProjects.includes(p.id));
  const someSelected = sortedProjects.some(p => selectedProjects.includes(p.id));

  return (
    <TableContainer component={Paper}>
      <Table>
        <TableHead>
          <TableRow>
            <TableCell padding="checkbox">
              <Checkbox
                checked={allSelected}
                indeterminate={someSelected && !allSelected}
                onChange={() => onToggleAll(sortedProjects.map(p => p.id))}
              />
            </TableCell>
            <TableCell>Project ID</TableCell>
            <TableCell>Project Name</TableCell>
            <TableCell>Loan App ID</TableCell>
            <TableCell>System Size</TableCell>
            <TableCell>Job Start</TableCell>
            <TableCell>PO Status</TableCell>
            <TableCell align="right">Actions</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {sortedProjects.map((project) => (
            <TableRow key={project.id} hover>
              <TableCell padding="checkbox">
                <Checkbox
                  checked={selectedProjects.includes(project.id)}
                  onChange={() => onToggleProject(project.id)}
                />
              </TableCell>
              <TableCell>
                <Link
                  href={`https://sunrise.gofreedompower.com/residential/projects/${project.id}/pulse`}
                  target="_blank"
                  rel="noopener noreferrer"
                  sx={{ color: 'primary.main' }}
                >
                  {project.id}
                </Link>
              </TableCell>
              <TableCell>{project.name}</TableCell>
              <TableCell>
                {project.loan_application_id ? (
                  <Link
                    href={`https://palmetto.finance/accounts/${project.loan_application_id}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    sx={{ color: 'primary.main' }}
                  >
                    {project.loan_application_id}
                  </Link>
                ) : (
                  'N/A'
                )}
              </TableCell>
              <TableCell>{project.system_size || 'N/A'}</TableCell>
              <TableCell>{formatDate(project.job_start)}</TableCell>
              <TableCell>
                {project.has_po ? (
                  <Chip
                    icon={<CheckCircleIcon />}
                    label={
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                        Has PO - Open in Netsuite
                        <OpenInNewIcon sx={{ fontSize: '0.875rem' }} />
                      </Box>
                    }
                    color="success"
                    size="small"
                    component={Link}
                    href={project.po_link}
                    target="_blank"
                    clickable
                  />
                ) : (
                  <Chip label="No PO" color="default" size="small" />
                )}
              </TableCell>
              <TableCell align="right">
                <ProjectActionButton
                  project={project}
                  onGenerateSingle={onGenerateSingle}
                  onReturnMaterial={onReturnMaterial}
                />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
}
