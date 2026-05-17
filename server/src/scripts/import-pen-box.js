import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    imagesDir: 'D:\\Editing\\Done\\Pen Box\\Images',
    category: 'Pen Box',
    cloudinaryPublicIdPrefix: 'pen-box/no-logo',
    defaultPrice: 0,
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--images-dir') args.imagesDir = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--public-id-prefix') args.cloudinaryPublicIdPrefix = argv[++i];
    else if (a === '--default-price') args.defaultPrice = Number(argv[++i]);
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

function codeFromFile(filename) {
  const base = path.parse(filename).name;
  const m = base.match(/^(\d{1,2})$/);
  if (!m) return null;
  return `PENBOX-${String(Number(m[1])).padStart(2, '0')}`;
}

async function main() {
  assertConfig();
  const args = parseArgs(process.argv);

  const entries = await fs.readdir(args.imagesDir, { withFileTypes: true });
  const files = entries
    .filter((e) => e.isFile())
    .map((e) => e.name)
    .filter((n) => /\.(png|jpe?g|webp)$/i.test(n))
    .sort((a, b) => a.localeCompare(b));

  const results = [];

  for (const file of files) {
    const code = codeFromFile(file);
    if (!code) {
      results.push({ file, status: 'skipped', reason: 'unexpected filename' });
      continue;
    }

    const abs = path.join(args.imagesDir, file);
    const buffer = await fs.readFile(abs);

    let upload = null;
    if (!args.dryRun) {
      upload = await uploadImageBufferUnsigned({
        buffer,
        filename: file,
        publicId: `${args.cloudinaryPublicIdPrefix}/${code}`
      });
    }

    const productRow = {
      name: code,
      code,
      category: args.category,
      price: Number.isFinite(args.defaultPrice) ? args.defaultPrice : 0,
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
      if (error) throw new Error(`Supabase upsert failed for ${code}: ${error.message}`);
    }

    results.push({ code, status: args.dryRun ? 'dry_run' : 'imported', image_url: upload?.url ?? null });
  }

  const outPath = path.resolve(process.cwd(), 'pen_box_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

