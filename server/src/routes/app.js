import express from 'express';

export const appRouter = express.Router();

/**
 * Endpoint for mobile app to check for updates.
 * In a real scenario, this might check a database or a file on the server.
 */
appRouter.get('/version', (req, res) => {
  res.json({
    latestVersion: '1.2.0',
    buildNumber: 5,
    releaseDate: '2026-05-18',
    downloadUrl: 'https://github.com/Ashishkumarpy/B2B-Stock-App/releases/latest', 
    isCritical: false,
    releaseNotes: '• Premium Modern UI: Beautiful dark modes and HSL colors\n• Security: Targeted OTP device isolation\n• Stability: Automatic push token lifecycle mapping\n• Bug Fixes: Resolved catch-22 login notification state'
  });
});
