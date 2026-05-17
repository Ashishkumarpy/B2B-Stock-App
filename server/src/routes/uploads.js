import express from 'express';
import multer from 'multer';
import { authRequired, requireRole } from '../auth.js';
import { uploadImageBufferUnsigned, deleteImage } from '../cloudinary.js';

export const uploadsRouter = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

uploadsRouter.post(
  '/image',
  authRequired,
  requireRole(['admin']),
  upload.single('file'),
  async (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'file is required' });

    try {
      const out = await uploadImageBufferUnsigned({
        buffer: req.file.buffer,
        filename: req.file.originalname,
        folder: 'b2b-stock/products'
      });
      return res.json(out);
    } catch (e) {
      return res.status(500).json({ error: String(e?.message || e) });
    }
  }
);

uploadsRouter.delete('/:publicId(*)', authRequired, requireRole(['admin']), async (req, res) => {
  const { publicId } = req.params;
  if (!publicId) return res.status(400).json({ error: 'publicId is required' });

  try {
    const result = await deleteImage(publicId);
    return res.json({ result });
  } catch (e) {
    return res.status(500).json({ error: String(e?.message || e) });
  }
});
