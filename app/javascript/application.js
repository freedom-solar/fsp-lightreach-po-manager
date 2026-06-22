// Entry point for the build script in your package.json
import React from 'react';
import { createRoot } from 'react-dom/client';
import Dashboard from './components/Dashboard';
import LoginPage from './components/LoginPage';

console.log("PO Tool loaded");

// Initialize React app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  const rootElement = document.getElementById('react-root');

  if (rootElement) {
    const root = createRoot(rootElement);
    const isLoginPage = rootElement.dataset.page === 'login';

    if (isLoginPage) {
      root.render(<LoginPage />);
    } else {
      root.render(<Dashboard />);
    }
  }
});
