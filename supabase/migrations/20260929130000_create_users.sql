-- =============================================================================
-- LaqYan (لقيان) — sign-in accounts
--
-- WARNING: DEMO ONLY. Passwords are stored as plain text (as requested) so they
-- can be read and edited directly in the Supabase Table Editor. Never reuse a
-- real password here. The table is NOT readable through the API: the browser can
-- only ask public.login() "is this ID + password right?".
--
--   students sign in with student_id + password
--   admins   sign in with admin_name + password
--
-- Replaces the single shared admin password (private.admin_secret) from
-- 20260929120000_create_items.sql: the admin_* functions now take the admin's
-- name and password and check them against this table.
-- =============================================================================

create table public.users (
  id          bigint generated always as identity primary key,
  role        text not null check (role in ('student', 'admin')),
  student_id  text unique check (student_id ~ '^[0-9]{9}$'),              -- KSU student number
  admin_name  text check (char_length(btrim(admin_name)) between 2 and 60),
  password    text not null check (char_length(password) between 4 and 100),  -- plain text (demo)
  created_at  timestamptz not null default now(),
  constraint users_login_matches_role check (
    (role = 'student' and student_id is not null and admin_name is null) or
    (role = 'admin'   and admin_name is not null and student_id is null))
);

comment on table public.users is
  'LaqYan sign-in accounts (demo: plain-text passwords, not exposed to the API; checked by public.login).';

create unique index users_admin_name_key on public.users (lower(admin_name));

-- No API access at all: RLS on, no policies, no privileges for anon / authenticated.
alter table public.users enable row level security;
revoke all on public.users from anon, authenticated;

-- Demo accounts (password 12345 for all). Add more in the Table Editor.
insert into public.users (role, student_id, admin_name, password) values
  ('admin',   null,        'admin', '12345'),
  ('student', '443101234', null,    '12345'),
  ('student', '443105678', null,    '12345'),
  ('student', '444109876', null,    '12345');

-- -----------------------------------------------------------------------------
-- Sign-in check used by the entry screen. p_login is the student ID or admin name
-- (admin names are case-insensitive). Returns true when the account exists.
-- -----------------------------------------------------------------------------
create or replace function public.login(p_role text, p_login text, p_password text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users u
     where u.role = p_role
       and u.password = coalesce(p_password, '')
       and case when p_role = 'student' then u.student_id = btrim(coalesce(p_login, ''))
                else lower(u.admin_name) = lower(btrim(coalesce(p_login, ''))) end);
$$;

-- -----------------------------------------------------------------------------
-- Admin functions: same behaviour as before, now checked per admin account.
-- -----------------------------------------------------------------------------
drop function if exists public.admin_check(text);
drop function if exists public.admin_update_item(text, uuid, jsonb);
drop function if exists public.admin_delete_item(text, uuid);
drop function if exists public.admin_reset_demo(text);
drop function if exists private.is_admin(text);
drop table if exists private.admin_secret;

create or replace function private.is_admin(p_admin_name text, p_password text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.login('admin', p_admin_name, p_password);
$$;

create or replace function public.admin_update_item(p_admin_name text, p_password text, p_id uuid, p_item jsonb)
returns public.items
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.items;
begin
  if not private.is_admin(p_admin_name, p_password) then
    raise exception 'admin sign-in required' using errcode = '28000';
  end if;
  update public.items i set
    section        = coalesce(p_item->>'section', i.section),
    item_name      = coalesce(p_item->>'item_name', i.item_name),
    category       = coalesce(p_item->>'category', i.category),
    description    = coalesce(p_item->>'description', i.description),
    location       = coalesce(p_item->>'location', i.location),
    item_date      = coalesce((p_item->>'item_date')::date, i.item_date),
    contact_info   = coalesce(p_item->>'contact_info', i.contact_info),
    image_url      = case when p_item ? 'image_url' then nullif(p_item->>'image_url', '') else i.image_url end,
    name_en        = case when p_item ? 'name_en' then p_item->>'name_en' else i.name_en end,
    description_en = case when p_item ? 'description_en' then p_item->>'description_en' else i.description_en end
  where i.id = p_id
  returning i.* into result;
  if result.id is null then
    raise exception 'report not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

create or replace function public.admin_delete_item(p_admin_name text, p_password text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin(p_admin_name, p_password) then
    raise exception 'admin sign-in required' using errcode = '28000';
  end if;
  delete from public.items where id = p_id;
end;
$$;

create or replace function public.admin_reset_demo(p_admin_name text, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin(p_admin_name, p_password) then
    raise exception 'admin sign-in required' using errcode = '28000';
  end if;
  delete from public.items where true;
  perform private.load_demo_items();
end;
$$;

revoke all on function private.is_admin(text, text) from public, anon, authenticated;
revoke all on function public.login(text, text, text) from public;
revoke all on function public.admin_update_item(text, text, uuid, jsonb) from public;
revoke all on function public.admin_delete_item(text, text, uuid) from public;
revoke all on function public.admin_reset_demo(text, text) from public;
grant execute on function public.login(text, text, text) to anon, authenticated;
grant execute on function public.admin_update_item(text, text, uuid, jsonb) to anon, authenticated;
grant execute on function public.admin_delete_item(text, text, uuid) to anon, authenticated;
grant execute on function public.admin_reset_demo(text, text) to anon, authenticated;
