import { supabaseAdmin } from './supabase.js';

async function run() {
  try {
    console.log('1. Fetching a valid product from database...');
    const { data: products, error: prodErr } = await supabaseAdmin
      .from('products')
      .select('id,name,code,color_stocks')
      .limit(1);

    if (prodErr || !products || products.length === 0) {
      console.error('Failed to get product:', prodErr);
      return;
    }

    const product = products[0];
    console.log(`Using product: ${product.name} (ID: ${product.id}, Code: ${product.code})`);

    console.log('2. Requesting OTP for test worker 6309705929...');
    const reqOtpRes = await fetch('http://127.0.0.1:8080/auth/worker/request-otp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '6309705929' })
    });

    const otpJson = await reqOtpRes.json();
    console.log('OTP Request Response:', otpJson);

    if (!reqOtpRes.ok) {
      console.error('Failed to request OTP');
      return;
    }

    console.log('3. Verifying OTP...');
    const verifyRes = await fetch('http://127.0.0.1:8080/auth/worker/verify-otp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: '6309705929', otp: '123456' })
    });

    const verifyJson = await verifyRes.json();
    console.log('Verify Response:', verifyJson);

    if (!verifyRes.ok) {
      console.error('Failed to verify OTP');
      return;
    }

    const token = verifyJson.token;
    console.log('Token acquired:', token);

    console.log('4. Posting stock transaction...');
    const txPayload = {
      product_id: product.id,
      product_name: product.name,
      type: 'stock_in',
      quantity: 5,
      color_name: 'Default',
      notes: 'Test script transaction',
      warehouse_id: 'default',
      worker_name: 'Ashish'
    };

    console.log('Payload:', txPayload);

    const txRes = await fetch('http://127.0.0.1:8080/transactions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(txPayload)
    });

    console.log('Response Status:', txRes.status);
    const txJson = await txRes.json();
    console.log('Response JSON:', txJson);

  } catch (err) {
    console.error('Crash in script:', err);
  }
  process.exit(0);
}

run();
