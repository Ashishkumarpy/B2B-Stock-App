import { supabaseAdmin } from './supabase.js';

/**
 * Log user activity to the database activity_logs table.
 */
export async function logActivity({ actorId, actorName, actionType, description, metadata = {} }) {
  try {
    const { error } = await supabaseAdmin.from('activity_logs').insert({
      actor_id: actorId || null,
      actor_name: actorName || 'System',
      action_type: actionType,
      description: String(description),
      metadata: metadata || {}
    });
    if (error) {
      console.error('Failed to write activity log:', error.message);
    }
  } catch (err) {
    console.error('Error writing activity log:', err);
  }
}
