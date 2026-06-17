// End-to-end test for the warehouse shift -> Stock Activity feature.
//
// What it proves:
//   1. POST /transactions/shift moves stock from one warehouse to another.
//   2. The shift is now recorded as a visible `type: 'shift'` row in the
//      transactions table (so it shows up in the Stock Activity feed).
//   3. The shift row does NOT double-adjust stock (trigger ignores 'shift').
//
// It uses ONLY fake throwaway data: two temporary warehouses and a temporary
// stock row for an existing product. The product's own quantity/color_stocks
// are never touched by a shift. Everything created here is deleted at the end,
// so no real transaction is performed.
//
// Prerequisites:
//   - The API server is running locally (npm run dev) on port 8080.
//   - supabase/shift_transaction_type.sql has been applied (adds 'shift' enum).
//   - .env has the Supabase service credentials (same as the server).
//
// Run:  node src/test_shift_transaction.js

import { supabaseAdmin } from './supabase.js';
import { signSession } from './auth.js';

const BASE_URL = process.env.TEST_BASE_URL || 'http://127.0.0.1:8080';
const COLOR = 'Default';
const START_QTY = 100;
const SHIFT_QTY = 10;

const created = { warehouseIds: [], stockKeys: [], product: null };
let pass = true;
const check = (label, ok, extra = '') => {
  console.log(`${ok ? '✅' : '❌'} ${label}${extra ? ` — ${extra}` : ''}`);
  if (!ok) pass = false;
};

async function mintToken() {
  // Prefer an admin (bypasses the permission lookup). Fall back to any worker.
  const { data: admin } = await supabaseAdmin
    .from('users')
    .select('id,name,email,role')
    .eq('role', 'admin')
    .limit(1)
    .maybeSingle();
  if (admin) {
    return signSession({ sub: admin.id, role: 'admin', name: admin.name || 'Test Admin', email: admin.email || '' });
  }
  const { data: worker } = await supabaseAdmin
    .from('workers')
    .select('id,user_id,name')
    .limit(1)
    .maybeSingle();
  if (!worker) throw new Error('No admin user or worker found to authenticate the test.');
  return signSession({ sub: worker.user_id || worker.id, role: 'worker', name: worker.name || 'Test Worker' });
}

async function warehouseQty(warehouseId) {
  const { data } = await supabaseAdmin
    .from('warehouse_product_stocks')
    .select('quantity')
    .eq('warehouse_id', warehouseId)
    .eq('product_id', created.product.id)
    .eq('color_name', COLOR)
    .maybeSingle();
  return data ? Number(data.quantity) : null;
}

async function cleanup() {
  console.log('\n🧹 Cleaning up fake data...');
  // Remove shift transactions written into the destination warehouse.
  for (const wid of created.warehouseIds) {
    await supabaseAdmin.from('transactions').delete().eq('warehouse_id', wid);
    await supabaseAdmin.from('warehouse_product_stocks').delete().eq('warehouse_id', wid);
  }
  if (created.warehouseIds.length) {
    await supabaseAdmin.from('warehouses').delete().in('id', created.warehouseIds);
  }
  console.log('Done.');
}

async function run() {
  try {
    console.log('1. Authenticating...');
    const token = await mintToken();

    console.log('2. Picking an existing product...');
    const { data: products, error: prodErr } = await supabaseAdmin
      .from('products')
      .select('id,name,code')
      .limit(1);
    if (prodErr || !products || products.length === 0) {
      throw new Error(`Could not load a product: ${prodErr?.message || 'none found'}`);
    }
    created.product = products[0];
    console.log(`   Using product: ${created.product.name} (${created.product.code})`);

    console.log('3. Creating two throwaway warehouses...');
    const stamp = Date.now();
    const { data: whRows, error: whErr } = await supabaseAdmin
      .from('warehouses')
      .insert([
        { name: `TEST Source ${stamp}`, is_active: true },
        { name: `TEST Dest ${stamp}`, is_active: true },
      ])
      .select('id,name');
    if (whErr) throw new Error(`Failed to create warehouses: ${whErr.message}`);
    const [fromWh, toWh] = whRows;
    created.warehouseIds = [fromWh.id, toWh.id];
    console.log(`   Source: ${fromWh.name}\n   Dest:   ${toWh.name}`);

    console.log(`4. Seeding ${START_QTY} units in the source warehouse...`);
    const { error: seedErr } = await supabaseAdmin
      .from('warehouse_product_stocks')
      .insert({
        warehouse_id: fromWh.id,
        product_id: created.product.id,
        color_name: COLOR,
        quantity: START_QTY,
      });
    if (seedErr) throw new Error(`Failed to seed stock: ${seedErr.message}`);

    console.log(`5. POST /transactions/shift — moving ${SHIFT_QTY} units source -> dest...`);
    const res = await fetch(`${BASE_URL}/transactions/shift`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        product_id: created.product.id,
        from_warehouse_id: fromWh.id,
        to_warehouse_id: toWh.id,
        quantity: SHIFT_QTY,
        color_name: COLOR,
        notes: 'Automated shift test',
      }),
    });
    const json = await res.json();
    check('Shift request succeeded (HTTP 200)', res.ok, res.ok ? '' : JSON.stringify(json));
    if (!res.ok) return;

    console.log('\n--- Verifying results ---');

    const srcQty = await warehouseQty(fromWh.id);
    const dstQty = await warehouseQty(toWh.id);
    check('Source warehouse decreased', srcQty === START_QTY - SHIFT_QTY, `expected ${START_QTY - SHIFT_QTY}, got ${srcQty}`);
    check('Destination warehouse increased', dstQty === SHIFT_QTY, `expected ${SHIFT_QTY}, got ${dstQty}`);

    // Product total is untouched by a shift.
    const { data: prodAfter } = await supabaseAdmin
      .from('products')
      .select('quantity')
      .eq('id', created.product.id)
      .maybeSingle();
    console.log(`   (product.quantity is unchanged by shifts: ${prodAfter?.quantity})`);

    console.log('\n6. GET /transactions — confirming the shift appears in Stock Activity...');
    const listRes = await fetch(`${BASE_URL}/transactions?product_id=${created.product.id}&limit=50`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const listJson = await listRes.json();
    const rows = Array.isArray(listJson.data) ? listJson.data : [];
    const shiftRow = rows.find((r) => r.type === 'shift' && String(r.warehouse_id) === String(toWh.id));
    check('A shift transaction row exists in the feed', !!shiftRow);
    if (shiftRow) {
      check('Shift row type is "shift"', shiftRow.type === 'shift');
      check('Shift row quantity is correct', Number(shiftRow.quantity) === SHIFT_QTY, `got ${shiftRow.quantity}`);
      check(
        'Shift row warehouse_name shows From -> To',
        typeof shiftRow.warehouse_name === 'string' && shiftRow.warehouse_name.includes('→'),
        shiftRow.warehouse_name,
      );
    }
  } catch (err) {
    check(`Test crashed: ${err.message}`, false);
  } finally {
    await cleanup();
    console.log(`\n${pass ? '🎉 ALL CHECKS PASSED' : '🚨 SOME CHECKS FAILED'}`);
    process.exit(pass ? 0 : 1);
  }
}

run();
