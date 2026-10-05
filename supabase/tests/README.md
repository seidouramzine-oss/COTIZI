# Tests de la base de données

Tester les migrations sur un PostgreSQL local (sans Supabase) :

```bash
createdb cz
psql -d cz -v ON_ERROR_STOP=1 -f supabase/tests/local_supabase_stub.sql
psql -d cz -v ON_ERROR_STOP=1 -f supabase/migrations/20261005000000_init.sql
psql -d cz -f supabase/tests/scenario.sql
```

Chaque étape marquée « (doit échouer) » doit afficher une erreur ; les autres doivent réussir.
