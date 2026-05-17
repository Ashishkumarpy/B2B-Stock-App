import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final suppliersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = Supabase.instance.client;
  return supabase
      .from('suppliers')
      .stream(primaryKey: ['id'])
      .order('name')
      .map((data) => data);
});
