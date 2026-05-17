import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    xlsx: 'D:\\Editing\\Done\\pens\\METAL PEN PRICE LIST.xlsx',
    imagesDir: 'D:\\Editing\\Done\\pens\\No Logo',
    category: 'Pens (Metal)',
    headerRow: 1,
    // Choose MOQ 500 as base price unless overridden
    priceColumn: 'MOQ 500',
    cloudinaryPublicIdPrefix: 'pens/metal/no-logo',
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--xlsx') args.xlsx = argv[++i];
    else if (a === '--images-dir') args.imagesDir = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--header-row') args.headerRow = Number(argv[++i]);
    else if (a === '--price-column') args.priceColumn = argv[++i];
    else if (a === '--public-id-prefix') args.cloudinaryPublicIdPrefix = argv[++i];
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

function normalizeCode(code) {
  // "XG-MP 01" -> "XG-MP-01"
  const s = String(code).trim().replace(/\s+/g, ' ');
  const m = s.match(/^(XG-MP)\s*(\d{1,3})$/i);
  if (m) return `${m[1].toUpperCase()}-${String(Number(m[2])).padStart(2, '0')}`;
  return s.replace(/\s+/g, '-');
}

function idxFromNormalizedCode(codeStr) {
  const m = String(codeStr).match(/(\d{1,3})$/);
  return m ? Number(m[1]) : null;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

function pad3(n) {
  return String(n).padStart(3, '0');
}

async function main() {
  assertConfig();
  const args = parseArgs(process.argv);

  const XLSX = (await import('xlsx')).default;
  const wb = XLSX.readFile(args.xlsx, { cellDates: true });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null });

  const headerIdx = args.headerRow - 1;
  const header = rows[headerIdx];
  if (!header) throw new Error(`header row not found: ${args.headerRow}`);

  const colIdx = header.findIndex((h) => String(h || '').trim().toUpperCase() === String(args.priceColumn).trim().toUpperCase());
  if (colIdx < 0) throw new Error(`price column not found in header: ${args.priceColumn}`);

  const results = [];

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const code = row[1];
    const name = row[2];
    const color = row[3];
    const price = row[colIdx];
    if (!code) continue;

    const codeStr = normalizeCode(code);
    const idx = idxFromNormalizedCode(codeStr);
    const candidates = [];
    if (idx !== null) {
      // Observed naming: 02..09 use 2 digits, 10.. use 3 digits.
      if (idx >= 10) candidates.push(`XG-MP-${pad3(idx)}.jpg`);
      candidates.push(`XG-MP-${pad2(idx)}.jpg`);
    }
    candidates.push(`${codeStr}.jpg`);

    let imagePath = null;
    let imageFile = null;
    for (const c of candidates) {
      const p = path.join(args.imagesDir, c);
      try {
        await fs.access(p);
        imagePath = p;
        imageFile = c;
        break;
      } catch {
        // continue
      }
    }

    if (!imagePath) {
      results.push({ code: codeStr, status: 'skipped', reason: `missing image: ${candidates[0] || `${codeStr}.jpg`}` });
      continue;
    }
    const buffer = await fs.readFile(imagePath);

    let upload = null;
    if (!args.dryRun) {
      upload = await uploadImageBufferUnsigned({
        buffer,
        filename: imageFile,
        publicId: `${args.cloudinaryPublicIdPrefix}/${codeStr}`
      });
    }

    const descParts = [];
    if (name) descParts.push(`Name: ${String(name).trim()}`);
    if (color) descParts.push(`Color: ${String(color).trim()}`);
    const description = descParts.length ? descParts.join(' | ') : null;

    const productRow = {
      name: String(name || codeStr).trim(),
      code: codeStr,
      category: args.category,
      price: price ?? 0,
      unit: 'pcs',
      description,
      image_url: upload?.url ?? null,
      images: upload
        ? [
            {
              variant: 'no_logo',
              url: upload.url,
              public_id: upload.publicId,
              folder: `products/${args.cloudinaryPublicIdPrefix}`
            }
          ]
        : []
    };

    if (!args.dryRun) {
      const { error } = await supabaseAdmin
        .from('products')
        .upsert(productRow, { onConflict: 'code' });
      if (error) throw new Error(`Supabase upsert failed for ${codeStr}: ${error.message}`);
    }

    results.push({ code: codeStr, status: args.dryRun ? 'dry_run' : 'imported', image_url: upload?.url ?? null });
  }

  const outPath = path.resolve(process.cwd(), 'metal_pens_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
