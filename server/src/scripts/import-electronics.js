import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    xlsx: 'D:\\Editing\\Done\\Electronics\\ELECTRONICS AUG 2025.xlsx',
    imagesDir: 'D:\\Editing\\Done\\Electronics\\No Logo',
    searchRoot: 'D:\\Editing\\Done\\Electronics',
    category: 'Electronics',
    headerRow: 4,
    cloudinaryPublicIdPrefix: 'electronics/no-logo',
    onlyCodes: null,
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--xlsx') args.xlsx = argv[++i];
    else if (a === '--images-dir') args.imagesDir = argv[++i];
    else if (a === '--search-root') args.searchRoot = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--header-row') args.headerRow = Number(argv[++i]);
    else if (a === '--public-id-prefix') args.cloudinaryPublicIdPrefix = argv[++i];
    else if (a === '--only-codes') args.onlyCodes = String(argv[++i]).split(',').map((s) => s.trim()).filter(Boolean);
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

function getIndexFromCode(code) {
  const m = String(code).match(/(\d{3})$/);
  return m ? Number(m[1]) : null;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

async function maybeCompressJpeg(buffer) {
  // Unsigned uploads in this account are capped at 10MB; compress proactively.
  const maxBytes = 9.5 * 1024 * 1024;
  if (buffer.byteLength <= maxBytes) return buffer;

  const sharp = (await import('sharp')).default;
  return sharp(buffer)
    .rotate()
    .resize({ width: 2000, height: 2000, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 82, mozjpeg: true })
    .toBuffer();
}

async function main() {
  assertConfig();
  const args = parseArgs(process.argv);

  const xlsxPath = args.xlsx;
  const imagesDir = args.imagesDir;
  const searchRoot = args.searchRoot;

  const XLSX = (await import('xlsx')).default;
  const wb = XLSX.readFile(xlsxPath, { cellDates: true });
  const sheetName = wb.SheetNames[0];
  const ws = wb.Sheets[sheetName];

  // Convert to rows while preserving empty cells; then index by headerRow.
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: null });
  const headerIdx = args.headerRow - 1;
  if (!rows[headerIdx]) throw new Error(`header row not found: ${args.headerRow}`);

  const out = [];
  const results = [];
  const fileIndex = new Map();

  async function buildFileIndexOnce() {
    if (fileIndex.size) return;
    async function walk(dir) {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) await walk(full);
        else fileIndex.set(e.name, full);
      }
    }
    await walk(searchRoot);
  }

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const code = row[1];
    const color = row[2];
    const price = row[3];
    if (!code) continue;
    const codeStr = String(code).trim();
    if (args.onlyCodes && !args.onlyCodes.includes(codeStr)) continue;

    const idx = getIndexFromCode(codeStr);
    if (!idx) {
      results.push({ code: codeStr, status: 'skipped', reason: 'cannot parse index from code' });
      continue;
    }

    const imageFile = `XG-T${pad2(idx)}(No Logo).jpg`;
    let imagePath = path.join(imagesDir, imageFile);

    let buffer;
    try {
      buffer = await fs.readFile(imagePath);
    } catch {
      await buildFileIndexOnce();
      const alt = fileIndex.get(imageFile);
      if (!alt) {
        results.push({ code: codeStr, status: 'skipped', reason: `missing image: ${imageFile}` });
        continue;
      }
      imagePath = alt;
      buffer = await fs.readFile(imagePath);
    }

    let upload = null;
    if (!args.dryRun) {
      buffer = await maybeCompressJpeg(buffer);
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
      if (error) throw new Error(`Supabase upsert failed for ${code}: ${error.message}`);
    }

    out.push(productRow);
    results.push({ code: productRow.code, status: args.dryRun ? 'dry_run' : 'imported', image_url: upload?.url ?? null });
  }

  const outPath = path.resolve(process.cwd(), 'electronics_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
