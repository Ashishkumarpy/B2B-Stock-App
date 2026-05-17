import express from 'express';
import { supabaseAdmin } from '../supabase.js';
import { authRequired, requireRole } from '../auth.js';

export const productsRouter = express.Router();

productsRouter.get('/', authRequired, async (req, res) => {
  const limit = parseInt(req.query.limit) || 1000;
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const { data, error } = await supabaseAdmin
    .from('products')
    .select('*')
    .order('name', { ascending: true })
    .range(offset, offset + limit - 1);

  if (error) return res.status(500).json({ error: error.message });
  return res.json({ data });
});

productsRouter.post('/', authRequired, requireRole(['admin']), async (req, res) => {
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin.from('products').insert(payload).select('*').single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

productsRouter.put('/:id', authRequired, requireRole(['admin', 'manager', 'worker']), async (req, res) => {
  const id = req.params.id;
  const payload = req.body || {};
  const { data, error } = await supabaseAdmin
    .from('products')
    .update(payload)
    .eq('id', id)
    .select('*')
    .single();
  if (error) return res.status(400).json({ error: error.message });
  return res.json({ data });
});

productsRouter.delete('/:id', authRequired, requireRole(['admin']), async (req, res) => {
  const id = req.params.id;

  try {
    // 1. Fetch product to get image public IDs before deleting
    const { data: product, error: fetchError } = await supabaseAdmin
      .from('products')
      .select('images')
      .eq('id', id)
      .single();

    if (product && !fetchError) {
      const publicIds = (product.images || [])
        .map((img) => img.publicId)
        .filter(Boolean);

      if (publicIds.length > 0) {
        const { deleteImage } = await import('../cloudinary.js');
        // Delete images in parallel
        await Promise.allSettled(publicIds.map((pid) => deleteImage(pid)));
      }
    }

    // 2. Delete from DB
    const { error } = await supabaseAdmin.from('products').delete().eq('id', id);
    if (error) return res.status(400).json({ error: error.message });
    return res.json({ ok: true });
  } catch (err) {
    console.error('Product deletion error:', err);
    return res.status(500).json({ error: 'Internal server error during deletion' });
  }
});
