import express from 'express';
import { sendPushNotification } from '../notifications/push_service.js';

export const appRouter = express.Router();

// Memory cache for GitHub release info
let cachedVersion = {
  latestVersion: '1.2.0',
  buildNumber: 5,
  releaseDate: '2026-05-18',
  downloadUrl: 'https://github.com/Ashishkumarpy/B2B-Stock-App/releases/latest', 
  isCritical: false,
  releaseNotes: '• Premium Modern UI: Beautiful dark modes and HSL colors\n• Security: Targeted OTP device isolation\n• Stability: Automatic push token lifecycle mapping\n• Bug Fixes: Resolved catch-22 login notification state'
};
let cacheExpiry = 0; // Epoch ms

async function fetchLatestGitHubRelease() {
  try {
    const response = await fetch('https://api.github.com/repos/Ashishkumarpy/B2B-Stock-App/releases/latest', {
      headers: {
        'User-Agent': 'B2B-Stock-Server'
      }
    });
    if (!response.ok) {
      throw new Error(`GitHub API returned status ${response.status}`);
    }
    const data = await response.json();
    
    // Parse tag_name (e.g. "v1.2.0" -> "1.2.0")
    const tagName = String(data.tag_name || '1.2.0').replace(/^v/, '');
    
    // Try to find direct APK download link in assets
    let downloadUrl = data.html_url || 'https://github.com/Ashishkumarpy/B2B-Stock-App/releases/latest';
    if (data.assets && Array.isArray(data.assets)) {
      const apkAsset = data.assets.find(asset => asset.name && asset.name.endsWith('.apk'));
      if (apkAsset) {
        downloadUrl = apkAsset.browser_download_url;
        console.log('Found direct APK download URL on GitHub:', downloadUrl);
      }
    }

    cachedVersion = {
      latestVersion: tagName,
      buildNumber: 5, // Default/fallback build number
      releaseDate: data.published_at ? data.published_at.slice(0, 10) : new Date().toISOString().slice(0, 10),
      downloadUrl: downloadUrl,
      isCritical: false,
      releaseNotes: data.body || 'New features and bug fixes.'
    };
    
    // Cache valid for 30 minutes to stay clear of rate limits
    cacheExpiry = Date.now() + 30 * 60 * 1000;
    console.log('Successfully refreshed latest app version from GitHub releases:', cachedVersion.latestVersion);
  } catch (error) {
    console.error('Failed to fetch latest version from GitHub:', error);
    // Keep using the last cached version as fallback
  }
}

/**
 * Endpoint for mobile app to check for updates.
 */
appRouter.get('/version', async (req, res) => {
  if (Date.now() > cacheExpiry) {
    await fetchLatestGitHubRelease();
  }
  res.json(cachedVersion);
});

/**
 * Webhook endpoint for GitHub to notify when a new release is published.
 * Setup this webhook in GitHub Repo settings -> Webhooks -> Add Webhook:
 * Payload URL: https://<your-server-url>/app/github-webhook
 * Content type: application/json
 * Event trigger: Releases
 */
appRouter.post('/github-webhook', async (req, res) => {
  const payload = req.body || {};
  const action = payload.action;
  const release = payload.release;

  console.log('Received GitHub webhook. Action:', action);

  if (action === 'published' && release) {
    const tagName = String(release.tag_name || '').replace(/^v/, '');
    
    // Try to find direct APK download link in assets
    let downloadUrl = release.html_url || 'https://github.com/Ashishkumarpy/B2B-Stock-App/releases/latest';
    if (release.assets && Array.isArray(release.assets)) {
      const apkAsset = release.assets.find(asset => asset.name && asset.name.endsWith('.apk'));
      if (apkAsset) {
        downloadUrl = apkAsset.browser_download_url;
        console.log('Webhook found direct APK download URL:', downloadUrl);
      }
    }

    const notes = release.body || 'New update is available.';

    if (tagName) {
      // 1. Instantly update server cache with the new release info
      cachedVersion = {
        latestVersion: tagName,
        buildNumber: 5,
        releaseDate: release.published_at ? release.published_at.slice(0, 10) : new Date().toISOString().slice(0, 10),
        downloadUrl: downloadUrl,
        isCritical: false,
        releaseNotes: notes
      };
      cacheExpiry = Date.now() + 30 * 60 * 1000; // Reset expiry

      console.log('GitHub webhook updated server cache to latest version:', tagName);

      // 2. Broadcast push notification to all mobile devices
      try {
        await sendPushNotification({
          title: 'New Update Available 🚀',
          body: `Version v${tagName} is now available! Tap to update and see what's new.`,
          data: {
            type: 'app_update',
            latestVersion: tagName,
            downloadUrl: downloadUrl,
            releaseNotes: notes
          },
          apps: ['mobile']
        });
        console.log('Successfully broadcasted update push notification to all devices.');
      } catch (pushError) {
        console.error('Failed to send update push notification:', pushError);
      }
    }
  }

  res.json({ received: true });
});
