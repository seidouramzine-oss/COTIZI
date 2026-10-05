// Connexion au projet Supabase de COTIZI.
// La clé publique (« publishable ») l'est par nature : les données sont protégées par
// les règles d'accès (RLS) définies dans supabase/migrations.
// Valeurs remplaçables à la compilation :
//   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://YOUR-PROJECT.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'YOUR-PUBLISHABLE-KEY',
);
