import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

// Load env from the root of server
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
  const email = 'jain556@gmail.com';
  const password = 'jain556';
  
  console.log(`Creating user in Supabase Auth: ${email}...`);
  
  // 1. Create the user in Auth
  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name: 'Jain Admin' }
  });

  if (authError) {
    if (authError.message.includes('already registered') || authError.message.includes('already exists')) {
      console.log('User is already registered in Auth. Fetching user instead...');
      // Fetch user from auth
      const { data: { users }, error: listError } = await supabase.auth.admin.listUsers();
      if (listError) throw listError;
      const user = users.find(u => u.email === email);
      if (!user) throw new Error('User not found in list');
      
      console.log(`Found existing user with ID: ${user.id}`);
      await updateRole(user.id, email);
    } else {
      throw authError;
    }
  } else {
    const user = authData.user;
    console.log(`User created successfully with ID: ${user.id}`);
    await updateRole(user.id, email);
  }
}

async function updateRole(userId, email) {
  console.log(`Setting role to 'admin' in public.users table for ID: ${userId}...`);
  
  // Update public.users
  const { data, error } = await supabase
    .from('users')
    .upsert({
      id: userId,
      name: 'Jain Admin',
      email: email,
      role: 'admin'
    }, { onConflict: 'id' });

  if (error) {
    throw error;
  }
  
  console.log('--------------------------------------------------');
  console.log('🎉 SUCCESS! Admin account created/updated successfully!');
  console.log(`📧 Email: ${email}`);
  console.log('🔑 Password: jain556');
  console.log('👑 Role: admin');
  console.log('--------------------------------------------------');
}

main().catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
