import { v2 as cloudinary } from 'cloudinary';
import { config } from './config.js';

// Configure Cloudinary SDK
cloudinary.config({
  cloud_name: config.cloudinary.cloudName,
  api_key: config.cloudinary.apiKey,
  api_secret: config.cloudinary.apiSecret,
});

/**
 * Deletes an image from Cloudinary by its public ID.
 */
export async function deleteImage(publicId) {
  if (!publicId) return;
  try {
    const result = await cloudinary.uploader.destroy(publicId);
    return result;
  } catch (err) {
    console.error('Cloudinary delete failed:', err);
    throw err;
  }
}

/**
 * Uploads an image buffer to Cloudinary using the SDK (signed upload).
 */
export async function uploadImageBuffer({ buffer, folder, publicId }) {
  return new Promise((resolve, reject) => {
    const options = {
      folder: folder || 'b2b-stock/products',
      resource_type: 'auto',
    };
    if (publicId) options.public_id = publicId;

    const uploadStream = cloudinary.uploader.upload_stream(options, (error, result) => {
      if (error) {
        console.error('Cloudinary SDK Upload Error:', error);
        return reject(error);
      }
      resolve({
        url: result.secure_url,
        publicId: result.public_id,
      });
    });

    uploadStream.end(buffer);
  });
}

// Alias for backward compatibility if needed, but now using the signed SDK method
export const uploadImageBufferUnsigned = uploadImageBuffer;
