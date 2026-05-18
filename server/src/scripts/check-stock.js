import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function main() {
  console.log('Fetching products and stock from Supabase...');
  const { data: products, error } = await supabase
    .from('products')
    .select('id, name, code, quantity, color_stocks');

  if (error) {
    console.error('Error fetching products:', error);
    return;
  }

  console.log('--- PRODUCTS IN DATABASE ---');
  let totalStock = 0;
  for (const p of products) {
    console.log(`📦 ${p.code} | ${p.name} | Total Qty: ${p.quantity} | Color Stocks: ${JSON.stringify(p.color_stocks)}`);
    totalStock += p.quantity;
  }
  console.log('----------------------------');
  console.log(`Total Aggregate Stock across all products: ${totalStock}`);

  const { data: txs, error: txError } = await supabase
    .from('transactions')
    .select('id, product_name, type, quantity');
  
  if (txError) {
    console.error('Error fetching transactions:', txError);
  } else {
    console.log(`Transactions count in DB: ${txs.length}`);
  }
}

main();
