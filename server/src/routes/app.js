import express from 'express';

export const appRouter = express.Router();

/**
 * Endpoint for mobile app to check for updates.
 * In a real scenario, this might check a database or a file on the server.
 */
appRouter.get('/version', (req, res) => {
  res.json({
    latestVersion: '1.0.2',
    buildNumber: 3,
    releaseDate: '2026-05-16',
    // Mock URL for testing
    downloadUrl: 'https://github.com/your-repo/releases/latest', 
    isCritical: false,
    releaseNotes: '• Premium Modern UI: New grid-based product cards\n• Performance: Faster image loading with Cloudinary\n• Stability: Fixed layout overflows and improved offline sync'
  });
});
