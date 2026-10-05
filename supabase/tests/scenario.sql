-- Scénario de bout en bout : à lancer après local_supabase_stub.sql et les migrations.
-- Les lignes « (doit échouer) » doivent afficher une ERREUR.
\set VERBOSITY terse
-- utilisateurs
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','t@x','{"signup":"cotizi"}','{"phone":"+22901000000","full_name":"Tontinier"}'),
 ('00000000-0000-0000-0000-0000000000a1','a@x','{"signup":"cotizi"}','{"phone":"+22901000001","full_name":"Alice"}'),
 ('00000000-0000-0000-0000-0000000000b1','b@x','{"signup":"cotizi"}','{"phone":"+22901000002","full_name":"Bob"}'),
 ('00000000-0000-0000-0000-0000000000c1','c@x','{"signup":"cotizi"}','{"phone":"+22901000003","full_name":"Chloe"}'),
 ('00000000-0000-0000-0000-0000000000d1','d@x','{"signup":"cotizi"}','{"phone":"+22901000004","full_name":"David"}');
\echo '== inscription sans app_metadata (doit échouer)'
insert into auth.users (email, raw_user_meta_data) values ('hack@x','{"phone":"+1","full_name":"Hack"}');

create or replace function public.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
grant execute on function public.as_user(text) to authenticated;

set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000a');
\echo '== T crée une tontine cagnotte + groupe'
insert into tontines (name, type) values ('Tontine du marché', 'cagnotte');
insert into groups (tontine_id, name, member_count, contribution_amount, frequency, start_date, commission_type, commission_value)
 select id, 'Groupe 1', 3, 10000, 'weekly', '2026-10-10', 'percent', 5 from tontines where name='Tontine du marché';
\echo '== commission fixe > cagnotte (doit échouer)'
insert into groups (tontine_id, name, member_count, contribution_amount, frequency, start_date, commission_type, commission_value)
 select id, 'Bad', 3, 10000, 'weekly', '2026-10-10', 'fixed', 40000 from tontines where name='Tontine du marché';
\echo '== groupe dans une tontine carnet (doit échouer)'
insert into tontines (name, type) values ('Carnets', 'carnet');
insert into groups (tontine_id, name, member_count, contribution_amount, frequency, start_date)
 select id, 'Bad', 3, 10000, 'weekly', '2026-10-10' from tontines where name='Carnets';
select invite_code as gcode from groups where name='Groupe 1' \gset
\echo '== T rejoint son propre groupe (doit échouer)'
select join_with_code(:'gcode');

select as_user('00000000-0000-0000-0000-0000000000a1');
\echo '== A ne voit pas le groupe avant de rejoindre (0)'
select count(*) from groups;
select join_with_code(lower(:'gcode')) is not null as a_joined;
\echo '== A tire avant ouverture (doit échouer)'
select draw_lot((select id from groups));
select as_user('00000000-0000-0000-0000-0000000000b1'); select join_with_code(:'gcode') is not null as b_joined;
select as_user('00000000-0000-0000-0000-00000000000a');
\echo '== tirage sur groupe incomplet (doit échouer)'
select start_draw((select id from groups where name='Groupe 1'));
select as_user('00000000-0000-0000-0000-0000000000c1'); select join_with_code(:'gcode') is not null as c_joined;
select as_user('00000000-0000-0000-0000-0000000000d1');
\echo '== D rejoint groupe complet (doit échouer)'
select join_with_code(:'gcode');
\echo '== code invalide'
select join_with_code('ZZZZZZ');
\echo '== D ne voit pas les profils de A (1 = lui-même)'
select count(*) from profiles;

select as_user('00000000-0000-0000-0000-00000000000a');
select start_draw((select id from groups where name='Groupe 1'));
select status from groups where name='Groupe 1';
select as_user('00000000-0000-0000-0000-0000000000a1');
\echo '== A tire'
select draw_lot((select id from groups)) as a_pos;
select draw_lot((select id from groups)) as a_pos_again;
\echo '== A ne peut pas modifier le statut'
update groups set status='active';
\echo '== A ne peut pas insérer de membre'
insert into group_members (group_id, user_id) select id, '00000000-0000-0000-0000-0000000000d1' from groups;
select as_user('00000000-0000-0000-0000-00000000000a');
select finish_draw((select id from groups where name='Groupe 1'));
select p.full_name, m.draw_position from group_members m join profiles p on p.id=m.user_id order by 2;
select status from groups where name='Groupe 1';

select as_user('00000000-0000-0000-0000-0000000000a1');
\echo '== A voit B, C et T (4 profils)'
select count(*) from profiles;
\echo '== A déclare tour 1'
select declare_payment((select id from groups), 1, '00000000-0000-0000-0000-0000000000a1/p1.jpg') is not null as declared;
\echo '== doublon (doit échouer)'
select declare_payment((select id from groups), 1, '00000000-0000-0000-0000-0000000000a1/p2.jpg');
\echo '== mauvais chemin de preuve (doit échouer)'
select declare_payment((select id from groups), 2, '00000000-0000-0000-0000-0000000000b1/p.jpg');
\echo '== tour 4 inexistant (doit échouer)'
select declare_payment((select id from groups), 4, '00000000-0000-0000-0000-0000000000a1/p.jpg');
\echo '== A ne peut pas valider son paiement'
select review_payment((select id from payments limit 1), true);
select as_user('00000000-0000-0000-0000-0000000000b1');
\echo '== B ne voit pas le paiement de A (0)'
select count(*) from payments;
reset role;
insert into storage.objects (bucket_id, name) values ('proofs','00000000-0000-0000-0000-0000000000a1/p1.jpg');
set role authenticated;
\echo '== B ne voit pas la preuve de A (0)'
select count(*) from storage.objects;
select as_user('00000000-0000-0000-0000-00000000000a');
\echo '== T voit la preuve de A (1)'
select count(*) from storage.objects;
\echo '== refus sans raison (doit échouer)'
select review_payment((select id from payments limit 1), false, '  ');
select review_payment((select id from payments limit 1), false, 'Montant incorrect');
select status, rejection_reason from payments;
select as_user('00000000-0000-0000-0000-0000000000a1');
\echo '== A redéclare après refus'
select declare_payment((select id from groups), 1, '00000000-0000-0000-0000-0000000000a1/p3.jpg') is not null as redeclared;
select as_user('00000000-0000-0000-0000-00000000000a');
select review_payment((select id from payments where status='pending'), true);
\echo '== retraiter un paiement validé (doit échouer)'
select review_payment((select id from payments where status='approved'), false, 'x');
select tour_number, amount, status from payments order by declared_at;

\echo '== CARNET'
insert into carnets (tontine_id, label, case_amount) select id, 'Carnet 1', 500 from tontines where name='Carnets';
\echo '== carnet dans tontine cagnotte (doit échouer)'
insert into carnets (tontine_id, label, case_amount) select id, 'Bad', 500 from tontines where name='Tontine du marché';
select invite_code as ccode from carnets \gset
select as_user('00000000-0000-0000-0000-0000000000d1');
select join_with_code(:'ccode') ->> 'kind' as d_joined;
select count(*) as d_sees_carnet from carnets;
select declare_carnet_payment((select id from carnets), 30, '00000000-0000-0000-0000-0000000000d1/c1.jpg') is not null as declared30;
\echo '== 2 cases de plus (doit échouer : il en reste 1)'
select declare_carnet_payment((select id from carnets), 2, '00000000-0000-0000-0000-0000000000d1/c2.jpg');
select as_user('00000000-0000-0000-0000-0000000000a1');
\echo '== A rejoint carnet déjà pris (doit échouer)'
select join_with_code(:'ccode');
\echo '== A ne voit pas le carnet (0)'
select count(*) from carnets;
select as_user('00000000-0000-0000-0000-00000000000a');
select review_carnet_payment((select id from carnet_payments), true);
select case_count, amount, status from carnet_payments;
\echo '== T voit le profil du client D'
select full_name from profiles where id='00000000-0000-0000-0000-0000000000d1';
reset role;
set role anon;
\echo '== anon ne lit rien (permission denied)'
select count(*) from tontines;
