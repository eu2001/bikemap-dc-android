import 'package:supabase_flutter/supabase_flutter.dart';

/// BikeMap DC — dedicated Supabase project (us-west-2).
/// Same project as the iOS app so DC users share data across platforms.
class SupabaseConfig {
  static const String url = 'https://hobulqkujiczaakaucwz.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhvYnVscWt1amljemFha2F1Y3d6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1MzkzMDYsImV4cCI6MjA5NDExNTMwNn0.PNNEuLEhLK-H_SthDloN5yJcw_Z1SYTUVxQ6NlfEgcU';

  static Future<void> init() async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}

/// Shorthand: `supabase.from('pois')...`
final supabase = Supabase.instance.client;
