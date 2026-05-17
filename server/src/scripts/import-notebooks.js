import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    xlsx: "D:\\Editing\\Done\\Diary's\\NOTEBOOK.xlsx",
    imagesDir: "D:\\Editing\\Done\\Diary's\\images\\No Logo",
    category: 'Notebooks & Diaries',
    headerRow: 3,
    cloudinaryPublicIdPrefix: 'notebooks-diaries/no-logo',
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
  const m = String(code).match(/(\d{3})$/);
  return m ? Number(m[1]) : null;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

async function main() {
  assertConfig();
  const args = parseArgs(process.argv);

  const XLSX = (await import('xlsx')).default;
  const wb = XLSX.readFile(args.xlsx, { cellDates: true });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null });

  const headerIdx = args.headerRow - 1;
  if (!rows[headerIdx]) throw new Error(`header row not found: ${args.headerRow}`);

  const results = [];

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const code = row[1];
    const color = row[2];
    const price = row[3];
    if (!code) continue;

    const codeStr = String(code).trim();
    const idx = idxFromCode(codeStr);
    if (!idx) {
      results.push({ code: codeStr, status: 'skipped', reason: 'cannot parse index from code' });
      continue;
    }

    const imageFile = `NB-${pad2(idx)}(No Logo).jpg`;
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

    const description = color ? `Color: ${String(color).trim()}` : null;
    const productRow = {
      name: codeStr,
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

  const outPath = path.resolve(process.cwd(), 'notebooks_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

