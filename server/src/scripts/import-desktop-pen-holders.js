import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    xlsx: 'D:\\Editing\\Done\\Desktop Pen Holder\\DEKSTOP.xlsx',
    imagesDir: 'D:\\Editing\\Done\\Desktop Pen Holder\\Images\\No Logo',
    category: 'Desktop Pen Holder',
    headerRow: 1,
    cloudinaryPublicIdPrefix: 'desktop-pen-holders/no-logo',
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--xlsx') args.xlsx = argv[++i];
    else if (a === '--images-dir') args.imagesDir = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--header-row') args.headerRow = Number(argv[++i]);
    else if (a === '--public-id-prefix') args.cloudinaryPublicIdPrefix = argv[++i];
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

function idxFromCode(code) {
  const m = String(code).trim().match(/(\d{1,3})$/);
  return m ? Number(m[1]) : null;
}

function fileFromCode(code) {
  // Observed: XG-D01(No Logo).jpg and XG-D010(No Logo).jpg
  const idx = idxFromCode(code);
  if (idx === null) return null;
  const n = idx >= 10 ? String(idx).padStart(3, '0') : String(idx).padStart(2, '0');
  return `XG-D${n}(No Logo).jpg`;
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

  const codeCol = header.findIndex((v) => String(v || '').trim().toUpperCase().includes('PRODUCT CODE'));
  const priceCol = header.findIndex((v) => String(v || '').trim().toUpperCase() === 'PRICE');
  if (codeCol < 0) throw new Error('PRODUCT CODE column not found in header');
  if (priceCol < 0) throw new Error('PRICE column not found in header');

  const results = [];

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const code = row[codeCol];
    const price = row[priceCol];
    if (!code) continue;

    const codeStr = String(code).trim();
    if (!codeStr.toUpperCase().startsWith('XG-D')) {
      results.push({ code: codeStr, status: 'skipped', reason: 'not a desktop pen holder code (expected XG-D*)' });
      continue;
    }
    const imageFile = fileFromCode(codeStr);
    if (!imageFile) {
      results.push({ code: codeStr, status: 'skipped', reason: 'cannot map code to image filename' });
      continue;
    }

    const imagePath = path.join(args.imagesDir, imageFile);
    let buffer;
    try {
      buffer = await fs.readFile(imagePath);
    } catch {
      results.push({ code: codeStr, status: 'skipped', reason: `missing image: ${imageFile}` });
      continue;
    }

    let upload = null;
    if (!args.dryRun) {
      upload = await uploadImageBufferUnsigned({
        buffer,
        filename: imageFile,
        publicId: `${args.cloudinaryPublicIdPrefix}/${codeStr}`
      });
    }

    const productRow = {
      name: codeStr,
      code: codeStr,
      category: args.category,
      price: price ?? 0,
      unit: 'pcs',
      description: null,
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

  const outPath = path.resolve(process.cwd(), 'desktop_pen_holders_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
