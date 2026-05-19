const { Client } = require('pg');

const client = new Client({
  connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
});

async function run() {
  try {
    await client.connect();
    console.log('Connected');
    await client.query('ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cartons INTEGER;');
    await client.query('ALTER TABLE transactions ADD COLUMN IF NOT EXISTS pcs_per_carton INTEGER;');
    console.log('Columns added successfully');
  } catch (err) {
    console.error('Error:', err);
  } finally {
    await client.end();
  }
}

run();
