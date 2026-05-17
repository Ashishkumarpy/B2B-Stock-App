import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: Number(process.env.PORT || 8080),
  host: process.env.HOST || '0.0.0.0',
  nodeEnv: process.env.NODE_ENV || 'development',

  jwtSecret: process.env.SERVER_JWT_SECRET || '',

  supabaseUrl: process.env.SUPABASE_URL || '',
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY || '',
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY || '',

  cookieName: process.env.COOKIE_NAME || 'b2b_stock_session',
  cookieSecure: (process.env.COOKIE_SECURE || 'false').toLowerCase() === 'true',
  cookieSameSite: process.env.COOKIE_SAME_SITE || 'lax',

  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || '',
    uploadPreset: process.env.CLOUDINARY_UPLOAD_PRESET || '',
    apiKey: process.env.CLOUDINARY_API_KEY || '',
    apiSecret: process.env.CLOUDINARY_API_SECRET || ''
  },

  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID || '',
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
    privateKey: process.env.FIREBASE_PRIVATE_KEY || ''
  }
};

export function assertConfig() {
  const missing = [];
  if (!config.jwtSecret) missing.push('SERVER_JWT_SECRET');
  if (!config.supabaseUrl) missing.push('SUPABASE_URL');
  if (!config.supabaseAnonKey) missing.push('SUPABASE_ANON_KEY');
  if (!config.supabaseServiceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!config.cloudinary.cloudName) missing.push('CLOUDINARY_CLOUD_NAME');
  if (!config.cloudinary.uploadPreset) missing.push('CLOUDINARY_UPLOAD_PRESET');

  if (missing.length) {
    throw new Error(`Missing env vars: ${missing.join(', ')}`);
  }
}
