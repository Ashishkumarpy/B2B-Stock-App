import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Error: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not found in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function main() {
  console.log('🚀 Starting smart stock reset...');

  // 1. Fetch all products to process color stocks
  const { data: products, error: fetchError } = await supabase
    .from('products')
    .select('id, name, code, quantity, color_stocks');

  if (fetchError) {
    console.error('❌ Failed to fetch products:', fetchError);
    process.exit(1);
  }

  console.log(`📦 Loaded ${products.length} products. Resetting quantities while keeping color definitions...`);

  let updatedCount = 0;
  
  // We will update products in batches of 50 to prevent network throttling
  const batchSize = 50;
  for (let i = 0; i < products.length; i += batchSize) {
    const batch = products.slice(i, i + batchSize);
    
    const promises = batch.map(async (p) => {
      let updatedColorStocks = [];
      if (Array.isArray(p.color_stocks)) {
        updatedColorStocks = p.color_stocks.map((item) => {
          if (typeof item === 'object' && item !== null) {
            return { ...item, quantity: 0 };
          }
          return item;
        });
      }

      const { error: updateError } = await supabase
        .from('products')
        .update({
          quantity: 0,
          color_stocks: updatedColorStocks
        })
        .eq('id', p.id);

      if (updateError) {
        console.error(`❌ Failed to update product ${p.code}:`, updateError.message);
      } else {
        updatedCount++;
      }
    });

    await Promise.all(promises);
    console.log(`⏳ Progress: ${updatedCount}/${products.length} products reset...`);
  }

  // 2. Clear all warehouse specific stock records
  console.log('🧹 Clearing warehouse-specific stock records...');
  const { error: whError } = await supabase
    .from('warehouse_product_stocks')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000'); // Deletes all rows

  if (whError) {
    console.error('❌ Failed to clear warehouse stocks:', whError);
  } else {
    console.log('✅ Warehouse stocks cleared successfully.');
  }

  // 3. Clear all transaction logs
  console.log('🧹 Clearing transaction logs...');
  const { error: txError } = await supabase
    .from('transactions')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000'); // Deletes all rows

  if (txError) {
    console.error('❌ Failed to clear transactions:', txError);
  } else {
    console.log('✅ Transaction logs cleared successfully.');
  }

  console.log('\n--------------------------------------------------');
  console.log('🎉 SUCCESS! Smart stock reset completed successfully!');
  console.log(`📦 Reset ${updatedCount} products to 0 stock, keeping all color names intact.`);
  console.log('--------------------------------------------------');
}

main().catch((err) => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
