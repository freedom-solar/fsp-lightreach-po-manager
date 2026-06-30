// Entry point for the Link Hub page (built by esbuild from app/javascript/*.*).
import React from 'react';
import { createRoot } from 'react-dom/client';
import LinkHub from './components/LinkHub';

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('link-hub-root');
  if (container) {
    const root = createRoot(container);
    root.render(<LinkHub logoUrl={container.getAttribute('data-logo-url')} />);
  }
});