/**
 * lib/cloudinary.ts — Direct unsigned upload to Cloudinary
 *
 * Uses an unsigned upload preset (created via Cloudinary Admin API).
 * No server function or API Secret needed — safe for browser usage.
 *
 * Preset: b2b_stock_unsigned
 * Folder: products
 * Formats: jpg, jpeg, png, webp, gif (max 10 MB)
 *
 * Note on deletion:
 *   Cloudinary's Destroy API requires the API Secret and cannot be
 *   called from the browser. When an admin removes an image the record
 *   is deleted from Firestore; the Cloudinary asset becomes orphaned.
 *   Bulk-clean via Cloudinary Dashboard → Media Library → folder: products.
 */

const CLOUD_NAME    = process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME!;
const UPLOAD_PRESET = process.env.NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET!;
const UPLOAD_URL    = `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`;

export interface CloudinaryAsset {
  url: string;
  publicId: string;
}

// ── Upload a single file directly to Cloudinary ───────────────────────────
export function uploadToCloudinary(
  file: File,
  folder = 'products',
  onProgress?: (pct: number) => void
): Promise<CloudinaryAsset> {
  return new Promise((resolve, reject) => {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', UPLOAD_PRESET);
    formData.append('folder', folder);

    const xhr = new XMLHttpRequest();

    xhr.upload.addEventListener('progress', (evt) => {
      if (evt.lengthComputable && onProgress) {
        onProgress(Math.round((evt.loaded / evt.total) * 100));
      }
    });

    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        const data = JSON.parse(xhr.responseText) as {
          secure_url: string;
          public_id: string;
        };
        resolve({ url: data.secure_url, publicId: data.public_id });
      } else {
        reject(new Error(`Cloudinary upload failed [${xhr.status}]: ${xhr.responseText}`));
      }
    });

    xhr.addEventListener('error', () =>
      reject(new Error('Cloudinary upload: network error'))
    );
    xhr.addEventListener('abort', () =>
      reject(new Error('Cloudinary upload: aborted'))
    );

    xhr.open('POST', UPLOAD_URL);
    xhr.send(formData);
  });
}

// ── Delete — browser-only no-op (API Secret required for Destroy API) ─────
export async function deleteFromCloudinary(publicId: string): Promise<void> {
  // Cannot call Cloudinary Destroy API from the browser.
  // The publicId is logged so you can bulk-delete via the Cloudinary dashboard.
  console.info(
    '[Cloudinary] Asset will be orphaned (unsigned mode). To remove manually:\n' +
    `  Dashboard → Media Library → search public_id: ${publicId}`
  );
}
