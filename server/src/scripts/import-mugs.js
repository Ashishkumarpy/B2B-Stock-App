import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function parseArgs(argv) {
  const args = { json: null, folder: 'catalog/mugs/no-logo', dryRun: false };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--json') args.json = argv[++i];
    else if (a === '--folder') args.folder = argv[++i];
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

async function main() {
  assertConfig();

  const args = parseArgs(process.argv);
  const defaultJson = path.resolve(__dirname, '../../../mugs_import.json');
  const jsonPath = path.resolve(args.json || defaultJson);

  const raw = await fs.readFile(jsonPath, 'utf-8');
  const items = JSON.parse(raw);

  const results = [];

  for (const item of items) {
    const code = String(item.code || '').trim();
    if (!code) continue;

    const imagePath = item.no_logo_path;
    if (!imagePath) {
      results.push({ code, status: 'skipped', reason: 'missing no_logo_path' });
      continue;
    }

    const buffer = await fs.readFile(imagePath);
    const filename = path.basename(imagePath);

    let upload = null;
    if (!args.dryRun) {
      upload = await uploadImageBufferUnsigned({
        buffer,
        filename,
        folder: args.folder,
        publicId: code
      });
    }

    const descriptionParts = [];
    if (item.color) descriptionParts.push(`Color: ${item.color}`);
    const description = descriptionParts.length ? descriptionParts.join(' | ') : null;

    const productRow = {
      name: item.name || code,
      code,
      category: item.category || 'Mugs',
      price: item.price_inr ?? null,
      unit: 'pcs',
      description,
      image_url: upload?.url ?? null,
      images: upload
        ? [{ variant: 'no_logo', url: upload.url, public_id: upload.publicId, folder: args.folder }]
        : []
    };

    if (!args.dryRun) {
      const { error } = await supabaseAdmin
        .from('products')
        .upsert(productRow, { onConflict: 'code' });
      if (error) throw new Error(`Supabase upsert failed for ${code}: ${error.message}`);
    }

    results.push({
      code,
      status: args.dryRun ? 'dry_run' : 'imported',
      image_url: upload?.url ?? null
    });
  }

  const outPath = path.resolve(process.cwd(), 'mugs_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
