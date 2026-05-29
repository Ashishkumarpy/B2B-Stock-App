import { supabaseAdmin } from './supabase.js';

/**
 * Log user activity to the database activity_logs table.
 */
export async function logActivity({ actorId, workerActorId, actorName, actionType, description, metadata = {} }) {
  try {
    let realActorId = actorId;
    let realWorkerActorId = workerActorId;

    // Auto-detect if actorId is actually a worker_id (if not present in public.users)
    if (realActorId && !realWorkerActorId) {
      const { data: user } = await supabaseAdmin
        .from('users')
        .select('id')
        .eq('id', realActorId)
        .maybeSingle();

      if (!user) {
        realWorkerActorId = realActorId;
        realActorId = null;
      }
    }

    const { error } = await supabaseAdmin.from('activity_logs').insert({
      actor_id: realActorId || null,
      worker_actor_id: realWorkerActorId || null,
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
