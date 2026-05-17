import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    imagesDir: null,
    // If not provided, uses filename (without extension) as code
    codeRegex: null,
    category: 'Uncategorized',
    publicIdPrefix: 'misc/no-logo',
    defaultPrice: 0,
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--images-dir') args.imagesDir = argv[++i];
    else if (a === '--code-regex') args.codeRegex = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--public-id-prefix') args.publicIdPrefix = argv[++i];
    else if (a === '--default-price') args.defaultPrice = Number(argv[++i]);
    else throw new Error(`Unknown arg: ${a}`);
  }

  if (!args.imagesDir) throw new Error('--images-dir is required');
  return args;
}

function codeFromFilename({ filename, regexStr }) {
  const base = path.parse(filename).name;
  if (!regexStr) return base;
  const re = new RegExp(regexStr, 'i');
  const m = base.match(re);
  if (!m) return null;
  return (m.groups?.code || m[1] || base).trim();
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
    const code = codeFromFilename({ filename: file, regexStr: args.codeRegex });
    if (!code) {
      results.push({ file, status: 'skipped', reason: 'code regex did not match' });
      continue;
    }

    const abs = path.join(args.imagesDir, file);
    const buffer = await fs.readFile(abs);

    let upload = null;
    if (!args.dryRun) {
      upload = await uploadImageBufferUnsigned({
        buffer,
        filename: file,
        publicId: `${args.publicIdPrefix}/${code}`
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
              folder: `products/${args.publicIdPrefix}`
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

  const outPath = path.resolve(process.cwd(), `image_only_${args.category.replace(/[^a-z0-9]+/gi, '_').toLowerCase()}.json`);
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

