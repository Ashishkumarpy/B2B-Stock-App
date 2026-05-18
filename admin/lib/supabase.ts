import { createClient } from '@supabase/supabase-js';

const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://itojengshxuxuarljomc.supabase.co';
const supabaseAnonKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_uaK-4d0HllpDttD8itUuZw_QMRkEIbi';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
