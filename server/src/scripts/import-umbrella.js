import fs from 'node:fs/promises';
import path from 'node:path';

import { assertConfig } from '../config.js';
import { uploadImageBufferUnsigned } from '../cloudinary.js';
import { supabaseAdmin } from '../supabase.js';

function parseArgs(argv) {
  const args = {
    dir: 'D:\\Editing\\Done\\Umbrella',
    glob: /^XG-U\d+\.(jpe?g|png|webp)$/i,
    category: 'Umbrella',
    cloudinaryPublicIdPrefix: 'umbrella/no-logo',
    defaultPrice: 0,
    dryRun: false
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--dir') args.dir = argv[++i];
    else if (a === '--category') args.category = argv[++i];
    else if (a === '--public-id-prefix') args.cloudinaryPublicIdPrefix = argv[++i];
    else if (a === '--default-price') args.defaultPrice = Number(argv[++i]);
    else throw new Error(`Unknown arg: ${a}`);
  }

  return args;
}

async function main() {
  assertConfig();
  const args = parseArgs(process.argv);

  const files = (await fs.readdir(args.dir)).filter((n) => args.glob.test(n)).sort();
  if (!files.length) throw new Error(`No matching images found in: ${args.dir}`);

  const results = [];

  for (const file of files) {
    const code = path.parse(file).name.trim();
    const abs = path.join(args.dir, file);
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
              folder: args.cloudinaryPublicIdPrefix
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

  const outPath = path.resolve(process.cwd(), 'umbrella_import_results.json');
  await fs.writeFile(outPath, JSON.stringify(results, null, 2), 'utf-8');
  console.log(`Done. Wrote ${results.length} results to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
