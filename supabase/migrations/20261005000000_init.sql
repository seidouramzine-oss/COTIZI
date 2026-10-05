-- COTIZI : schéma initial
-- Deux types de tontines :
--   * cagnotte : tontine -> groupes -> membres (tirage au sort) -> paiements par tour
--   * carnet   : tontine -> carnets de 31 cases -> un client -> paiements de cases

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.tontine_type as enum ('cagnotte', 'carnet');
create type public.frequency as enum ('daily', 'weekly', 'biweekly', 'monthly');
create type public.commission_type as enum ('percent', 'fixed');
create type public.group_status as enum ('recruiting', 'drawing', 'active');
create type public.payment_status as enum ('pending', 'approved', 'rejected');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text not null unique,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 60),
  created_at timestamptz not null default now()
);

create table public.tontines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  type public.tontine_type not null,
  created_at timestamptz not null default now()
);
create index tontines_owner_id_idx on public.tontines (owner_id);

-- Code d'invitation lisible (sans 0/O, 1/I/L)
create function public.generate_invite_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 6);
$$;

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  tontine_id uuid not null references public.tontines (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  member_count int not null check (member_count between 2 and 100),
  contribution_amount bigint not null check (contribution_amount > 0),
  frequency public.frequency not null,
  start_date date not null,
  commission_type public.commission_type not null default 'percent',
  commission_value numeric(14, 2) not null default 0 check (commission_value >= 0),
  invite_code text not null unique default public.generate_invite_code(),
  status public.group_status not null default 'recruiting',
  created_at timestamptz not null default now(),
  constraint groups_commission_check check (
    (commission_type = 'percent' and commission_value <= 100)
    or (commission_type = 'fixed' and commission_value <= member_count * contribution_amount)
  )
);
create index groups_tontine_id_idx on public.groups (tontine_id);

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  draw_position int check (draw_position >= 1),
  drawn_at timestamptz,
  joined_at timestamptz not null default now(),
  unique (group_id, user_id),
  unique (group_id, draw_position)
);
create index group_members_user_id_idx on public.group_members (user_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  tour_number int not null check (tour_number >= 1),
  amount bigint not null check (amount > 0),
  proof_path text not null,
  status public.payment_status not null default 'pending',
  rejection_reason text,
  declared_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint payments_rejection_reason_check check (
    status <> 'rejected' or char_length(btrim(coalesce(rejection_reason, ''))) > 0
  )
);
create index payments_group_id_idx on public.payments (group_id);
create index payments_user_id_idx on public.payments (user_id);
-- Un seul paiement en attente ou validé par membre et par tour
create unique index payments_one_active_per_tour
  on public.payments (group_id, user_id, tour_number)
  where status in ('pending', 'approved');

create table public.carnets (
  id uuid primary key default gen_random_uuid(),
  tontine_id uuid not null references public.tontines (id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 80),
  case_amount bigint not null check (case_amount > 0),
  case_count int not null default 31 check (case_count = 31),
  client_id uuid references public.profiles (id) on delete set null,
  invite_code text not null unique default public.generate_invite_code(),
  created_at timestamptz not null default now()
);
create index carnets_tontine_id_idx on public.carnets (tontine_id);
create index carnets_client_id_idx on public.carnets (client_id);

create table public.carnet_payments (
  id uuid primary key default gen_random_uuid(),
  carnet_id uuid not null references public.carnets (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  case_count int not null check (case_count between 1 and 31),
  amount bigint not null check (amount > 0),
  proof_path text not null,
  status public.payment_status not null default 'pending',
  rejection_reason text,
  declared_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint carnet_payments_rejection_reason_check check (
    status <> 'rejected' or char_length(btrim(coalesce(rejection_reason, ''))) > 0
  )
);
create index carnet_payments_carnet_id_idx on public.carnet_payments (carnet_id);
create index carnet_payments_user_id_idx on public.carnet_payments (user_id);

-- ---------------------------------------------------------------------------
-- Profil créé automatiquement à l'inscription (uniquement via la fonction
-- « signup », qui pose app_metadata.signup = 'cotizi')
-- ---------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_app_meta_data ->> 'signup', '') <> 'cotizi' then
    raise exception 'Inscription non autorisée';
  end if;
  insert into public.profiles (id, phone, full_name)
  values (
    new.id,
    new.raw_user_meta_data ->> 'phone',
    btrim(new.raw_user_meta_data ->> 'full_name')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Fonctions d'aide pour les règles d'accès (security definer pour éviter
-- la récursion entre politiques)
-- ---------------------------------------------------------------------------
create function public.is_tontine_owner(p_tontine_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.tontines t
    where t.id = p_tontine_id and t.owner_id = (select auth.uid())
  );
$$;

create function public.is_group_owner(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.groups g
    join public.tontines t on t.id = g.tontine_id
    where g.id = p_group_id and t.owner_id = (select auth.uid())
  );
$$;

create function public.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = (select auth.uid())
  );
$$;

create function public.is_carnet_owner(p_carnet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.carnets c
    join public.tontines t on t.id = c.tontine_id
    where c.id = p_carnet_id and t.owner_id = (select auth.uid())
  );
$$;

-- Le tontinier voit ses membres/clients ; les membres d'un même groupe se
-- voient entre eux ; membres et clients voient leur tontinier.
create function public.can_view_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_profile_id = (select auth.uid())
    or exists (
      select 1
      from public.group_members m
      join public.groups g on g.id = m.group_id
      join public.tontines t on t.id = g.tontine_id
      where m.user_id = p_profile_id and t.owner_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.carnets c
      join public.tontines t on t.id = c.tontine_id
      where c.client_id = p_profile_id and t.owner_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.group_members me
      join public.group_members other on other.group_id = me.group_id
      where me.user_id = (select auth.uid()) and other.user_id = p_profile_id
    )
    or exists (
      select 1
      from public.group_members me
      join public.groups g on g.id = me.group_id
      join public.tontines t on t.id = g.tontine_id
      where me.user_id = (select auth.uid()) and t.owner_id = p_profile_id
    )
    or exists (
      select 1
      from public.carnets c
      join public.tontines t on t.id = c.tontine_id
      where c.client_id = (select auth.uid()) and t.owner_id = p_profile_id
    );
$$;

create function public.can_view_tontine(p_tontine_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.tontines t
      where t.id = p_tontine_id and t.owner_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.groups g
      join public.group_members m on m.group_id = g.id
      where g.tontine_id = p_tontine_id and m.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.carnets c
      where c.tontine_id = p_tontine_id and c.client_id = (select auth.uid())
    );
$$;

create function public.tontine_type_of(p_tontine_id uuid)
returns public.tontine_type
language sql
stable
security definer
set search_path = ''
as $$
  select t.type from public.tontines t where t.id = p_tontine_id;
$$;

-- ---------------------------------------------------------------------------
-- Droits sur les tables : rien pour les visiteurs non connectés ; les
-- modifications sensibles (statuts, membres, paiements) passent par les RPC.
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.tontines, public.groups, public.group_members,
  public.payments, public.carnets, public.carnet_payments from anon, authenticated;
grant select on public.profiles, public.tontines, public.groups, public.group_members,
  public.payments, public.carnets, public.carnet_payments to authenticated;
grant insert on public.tontines, public.groups, public.carnets to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant update (name) on public.tontines to authenticated;

-- ---------------------------------------------------------------------------
-- Règles d'accès (RLS)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.tontines enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.payments enable row level security;
alter table public.carnets enable row level security;
alter table public.carnet_payments enable row level security;

-- profiles
create policy "profiles_select" on public.profiles
  for select to authenticated
  using ((select public.can_view_profile(id)));
create policy "profiles_update_self" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- tontines
create policy "tontines_select" on public.tontines
  for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.can_view_tontine(id)));
create policy "tontines_insert_owner" on public.tontines
  for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy "tontines_update_owner" on public.tontines
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- groups (statut modifié uniquement via les fonctions start_draw / draw_lot)
create policy "groups_select" on public.groups
  for select to authenticated
  using ((select public.is_tontine_owner(tontine_id)) or (select public.is_group_member(id)));
create policy "groups_insert_owner" on public.groups
  for insert to authenticated
  with check (
    (select public.is_tontine_owner(tontine_id))
    and (select public.tontine_type_of(tontine_id)) = 'cagnotte'
    and status = 'recruiting'
  );

-- group_members (ajout via join_with_code, tirage via draw_lot)
create policy "group_members_select" on public.group_members
  for select to authenticated
  using ((select public.is_group_owner(group_id)) or (select public.is_group_member(group_id)));

-- payments (déclaration via declare_payment, validation via review_payment)
create policy "payments_select" on public.payments
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_group_owner(group_id)));

-- carnets
create policy "carnets_select" on public.carnets
  for select to authenticated
  using (client_id = (select auth.uid()) or (select public.is_tontine_owner(tontine_id)));
create policy "carnets_insert_owner" on public.carnets
  for insert to authenticated
  with check (
    (select public.is_tontine_owner(tontine_id))
    and (select public.tontine_type_of(tontine_id)) = 'carnet'
    and client_id is null
  );

-- carnet_payments
create policy "carnet_payments_select" on public.carnet_payments
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_carnet_owner(carnet_id)));

-- ---------------------------------------------------------------------------
-- Actions (RPC)
-- ---------------------------------------------------------------------------

-- Rejoindre un groupe ou un carnet avec un code d'invitation
create function public.join_with_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_group public.groups;
  v_carnet public.carnets;
  v_owner uuid;
  v_count int;
begin
  if v_uid is null then
    raise exception 'Vous devez être connecté';
  end if;

  select * into v_group from public.groups where invite_code = v_code for update;
  if found then
    select owner_id into v_owner from public.tontines where id = v_group.tontine_id;
    if v_owner = v_uid then
      raise exception 'Vous êtes le tontinier de ce groupe';
    end if;
    if exists (select 1 from public.group_members where group_id = v_group.id and user_id = v_uid) then
      return jsonb_build_object('kind', 'group', 'id', v_group.id);
    end if;
    if v_group.status <> 'recruiting' then
      raise exception 'Ce groupe n''accepte plus de nouveaux membres';
    end if;
    select count(*) into v_count from public.group_members where group_id = v_group.id;
    if v_count >= v_group.member_count then
      raise exception 'Ce groupe est déjà complet';
    end if;
    insert into public.group_members (group_id, user_id) values (v_group.id, v_uid);
    return jsonb_build_object('kind', 'group', 'id', v_group.id);
  end if;

  select * into v_carnet from public.carnets where invite_code = v_code for update;
  if found then
    select owner_id into v_owner from public.tontines where id = v_carnet.tontine_id;
    if v_owner = v_uid then
      raise exception 'Vous êtes le tontinier de ce carnet';
    end if;
    if v_carnet.client_id = v_uid then
      return jsonb_build_object('kind', 'carnet', 'id', v_carnet.id);
    end if;
    if v_carnet.client_id is not null then
      raise exception 'Ce carnet a déjà un client';
    end if;
    update public.carnets set client_id = v_uid where id = v_carnet.id;
    return jsonb_build_object('kind', 'carnet', 'id', v_carnet.id);
  end if;

  raise exception 'Code d''invitation introuvable';
end;
$$;

-- Le tontinier lance le tirage au sort (groupe complet)
create function public.start_draw(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups;
  v_count int;
begin
  if not public.is_group_owner(p_group_id) then
    raise exception 'Seul le tontinier peut lancer le tirage';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if v_group.status <> 'recruiting' then
    raise exception 'Le tirage a déjà été lancé';
  end if;
  select count(*) into v_count from public.group_members where group_id = p_group_id;
  if v_count < v_group.member_count then
    raise exception 'Le groupe n''est pas encore complet (% / %)', v_count, v_group.member_count;
  end if;
  update public.groups set status = 'drawing' where id = p_group_id;
end;
$$;

-- Attribue un rang libre au hasard à un membre ; passe le groupe en « actif »
-- quand tout le monde a tiré.
create function public.assign_random_position(p_group_id uuid, p_member_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups;
  v_position int;
begin
  select * into v_group from public.groups where id = p_group_id;
  select pos into v_position
  from generate_series(1, v_group.member_count) as pos
  where not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.draw_position = pos
  )
  order by random()
  limit 1;

  update public.group_members
  set draw_position = v_position, drawn_at = now()
  where id = p_member_id;

  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and draw_position is null
  ) then
    update public.groups set status = 'active' where id = p_group_id;
  end if;
  return v_position;
end;
$$;
revoke execute on function public.assign_random_position(uuid, uuid) from public, anon, authenticated;

-- Un membre tire son rang
create function public.draw_lot(p_group_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups;
  v_member public.group_members;
begin
  select * into v_group from public.groups where id = p_group_id for update;
  select * into v_member from public.group_members
  where group_id = p_group_id and user_id = auth.uid();
  if not found then
    raise exception 'Vous n''êtes pas membre de ce groupe';
  end if;
  if v_member.draw_position is not null then
    return v_member.draw_position;
  end if;
  if v_group.status <> 'drawing' then
    raise exception 'Le tirage au sort n''est pas ouvert';
  end if;
  return public.assign_random_position(p_group_id, v_member.id);
end;
$$;

-- Le tontinier termine le tirage pour les membres qui n'ont pas encore tiré
create function public.finish_draw(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups;
  v_member_id uuid;
begin
  if not public.is_group_owner(p_group_id) then
    raise exception 'Seul le tontinier peut terminer le tirage';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if v_group.status <> 'drawing' then
    raise exception 'Le tirage au sort n''est pas en cours';
  end if;
  for v_member_id in
    select id from public.group_members
    where group_id = p_group_id and draw_position is null
    order by random()
  loop
    perform public.assign_random_position(p_group_id, v_member_id);
  end loop;
end;
$$;

-- Un membre déclare son paiement pour un tour, avec preuve
create function public.declare_payment(p_group_id uuid, p_tour_number int, p_proof_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups;
  v_id uuid;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'Vous n''êtes pas membre de ce groupe';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if v_group.status <> 'active' then
    raise exception 'Les paiements commencent après le tirage au sort';
  end if;
  if p_tour_number is null or p_tour_number < 1 or p_tour_number > v_group.member_count then
    raise exception 'Tour invalide';
  end if;
  if p_proof_path is null or split_part(p_proof_path, '/', 1) <> v_uid::text then
    raise exception 'Preuve de paiement invalide';
  end if;
  if exists (
    select 1 from public.payments
    where group_id = p_group_id and user_id = v_uid and tour_number = p_tour_number
      and status in ('pending', 'approved')
  ) then
    raise exception 'Un paiement est déjà déclaré pour ce tour';
  end if;
  insert into public.payments (group_id, user_id, tour_number, amount, proof_path)
  values (p_group_id, v_uid, p_tour_number, v_group.contribution_amount, p_proof_path)
  returning id into v_id;
  return v_id;
end;
$$;

-- Le tontinier valide ou refuse un paiement
create function public.review_payment(p_payment_id uuid, p_approve boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.payments;
begin
  select * into v_payment from public.payments where id = p_payment_id for update;
  if not found or not public.is_group_owner(v_payment.group_id) then
    raise exception 'Paiement introuvable';
  end if;
  if v_payment.status <> 'pending' then
    raise exception 'Ce paiement a déjà été traité';
  end if;
  if p_approve then
    update public.payments
    set status = 'approved', rejection_reason = null, reviewed_at = now()
    where id = p_payment_id;
  else
    if char_length(btrim(coalesce(p_reason, ''))) = 0 then
      raise exception 'Indiquez la raison du refus';
    end if;
    update public.payments
    set status = 'rejected', rejection_reason = btrim(p_reason), reviewed_at = now()
    where id = p_payment_id;
  end if;
end;
$$;

-- Le client déclare le paiement d'une ou plusieurs cases de son carnet
create function public.declare_carnet_payment(p_carnet_id uuid, p_case_count int, p_proof_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_carnet public.carnets;
  v_used int;
  v_id uuid;
begin
  select * into v_carnet from public.carnets where id = p_carnet_id for update;
  if not found or v_carnet.client_id is distinct from v_uid then
    raise exception 'Ce carnet ne vous appartient pas';
  end if;
  if p_case_count is null or p_case_count < 1 then
    raise exception 'Nombre de cases invalide';
  end if;
  if p_proof_path is null or split_part(p_proof_path, '/', 1) <> v_uid::text then
    raise exception 'Preuve de paiement invalide';
  end if;
  select coalesce(sum(case_count), 0) into v_used
  from public.carnet_payments
  where carnet_id = p_carnet_id and status in ('pending', 'approved');
  if v_used + p_case_count > v_carnet.case_count then
    raise exception 'Il ne reste que % case(s) à payer sur ce carnet', v_carnet.case_count - v_used;
  end if;
  insert into public.carnet_payments (carnet_id, user_id, case_count, amount, proof_path)
  values (p_carnet_id, v_uid, p_case_count, p_case_count * v_carnet.case_amount, p_proof_path)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.review_carnet_payment(p_payment_id uuid, p_approve boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment public.carnet_payments;
begin
  select * into v_payment from public.carnet_payments where id = p_payment_id for update;
  if not found or not public.is_carnet_owner(v_payment.carnet_id) then
    raise exception 'Paiement introuvable';
  end if;
  if v_payment.status <> 'pending' then
    raise exception 'Ce paiement a déjà été traité';
  end if;
  if p_approve then
    update public.carnet_payments
    set status = 'approved', rejection_reason = null, reviewed_at = now()
    where id = p_payment_id;
  else
    if char_length(btrim(coalesce(p_reason, ''))) = 0 then
      raise exception 'Indiquez la raison du refus';
    end if;
    update public.carnet_payments
    set status = 'rejected', rejection_reason = btrim(p_reason), reviewed_at = now()
    where id = p_payment_id;
  end if;
end;
$$;

-- Droits d'exécution : uniquement les utilisateurs connectés
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.generate_invite_code() from public, anon;
grant execute on function public.generate_invite_code() to authenticated;
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.join_with_code(text)',
    'public.start_draw(uuid)',
    'public.draw_lot(uuid)',
    'public.finish_draw(uuid)',
    'public.declare_payment(uuid, int, text)',
    'public.review_payment(uuid, boolean, text)',
    'public.declare_carnet_payment(uuid, int, text)',
    'public.review_carnet_payment(uuid, boolean, text)',
    'public.is_tontine_owner(uuid)',
    'public.is_group_owner(uuid)',
    'public.is_group_member(uuid)',
    'public.is_carnet_owner(uuid)',
    'public.can_view_profile(uuid)',
    'public.can_view_tontine(uuid)',
    'public.tontine_type_of(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stockage des preuves de paiement (captures d'écran)
-- Chemin : <user_id>/<fichier>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proofs', 'proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do nothing;

create policy "proofs_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "proofs_select" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'proofs'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.payments p
        where p.proof_path = name and (select public.is_group_owner(p.group_id))
      )
      or exists (
        select 1 from public.carnet_payments cp
        where cp.proof_path = name and (select public.is_carnet_owner(cp.carnet_id))
      )
    )
  );
