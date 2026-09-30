-- =============================================================================
-- LaqYan (لقيان) — lost & found items
--
-- WARNING: DEMO / WORKSHOP SETUP ONLY — NOT FOR PRODUCTION.
-- This app has no user sign-in. The anon (public) key is shipped in the browser,
-- so ANYONE who opens the page can:
--   * read every report, including contact_info (phone / email),
--   * insert new reports,
--   * change any report's status (open <-> returned).
-- Admin edit / delete / restore go through the admin_* functions below, which only
-- check one shared password. Before real use: add Supabase Auth, limit insert/update
-- to signed-in users, hide contact_info behind a claim flow, and replace the shared
-- admin password with proper roles.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Table. Field names/values mirror index.html:
--   type -> report_type ('lost' | 'found')          section  ('male' | 'female')
--   returned (bool) -> status ('open' | 'returned')  returnedDate -> returned_date
--   name -> item_name   desc -> description   date -> item_date   contact -> contact_info
--   image (photo data URL) -> image_url   illus -> illustration (sample items only)
--   en.name / en.desc -> name_en / description_en (English texts of the sample items)
-- The app shows status as: returned -> 'تم التسليم', else report_type ('مفقود' / 'موجود').
-- -----------------------------------------------------------------------------
create table public.items (
  id              uuid primary key default gen_random_uuid(),
  report_type     text not null check (report_type in ('lost', 'found')),
  section         text not null check (section in ('male', 'female')),
  status          text not null default 'open' check (status in ('open', 'returned')),
  returned_date   date,
  item_name       text not null check (char_length(btrim(item_name)) between 1 and 120),
  category        text not null check (category in
                    ('headphones', 'keys', 'charger', 'wallet', 'electronics', 'clothing', 'other')),
  description     text not null default '' check (char_length(description) <= 2000),
  location        text not null check (location in (
                    'كلية الحاسب والمعلومات', 'كلية الهندسة', 'كلية العلوم', 'كلية إدارة الأعمال',
                    'المكتبة المركزية', 'الكافتيريا الرئيسية', 'المركز الطلابي', 'مسجد الجامعة',
                    'صالة الرياضة', 'مواقف الطلاب', 'البوابة الرئيسية', 'أخرى')),
  item_date       date not null check (item_date >= date '2020-01-01'),
  contact_info    text not null check (char_length(btrim(contact_info)) between 5 and 120),
  image_url       text check (image_url is null or char_length(image_url) <= 400000),  -- shrunk JPEG data URL
  illustration    text check (illustration is null or illustration ~ '^[a-z0-9-]{1,40}$'),
  name_en         text check (name_en is null or char_length(name_en) <= 120),
  description_en  text check (description_en is null or char_length(description_en) <= 2000),
  created_at      timestamptz not null default now(),
  constraint returned_date_matches_status check ((status = 'returned') = (returned_date is not null))
);

comment on table public.items is 'LaqYan lost & found reports (demo: public read/insert, status-only update).';

create index items_section_type_date_idx on public.items (section, report_type, item_date desc);

-- returned_date follows status automatically, so the browser only ever updates `status`.
create or replace function public.items_sync_returned_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'returned' and (old.status is distinct from 'returned' or new.returned_date is null) then
    new.returned_date := coalesce(new.returned_date, current_date);
  elsif new.status = 'open' then
    new.returned_date := null;
  end if;
  return new;
end;
$$;

create trigger items_sync_returned_date
before update of status on public.items
for each row execute function public.items_sync_returned_date();

-- -----------------------------------------------------------------------------
-- Row Level Security + column privileges
--   anon / authenticated: SELECT all rows, INSERT new reports, UPDATE only `status`.
--   No DELETE from the client (no policy and no privilege).
-- -----------------------------------------------------------------------------
alter table public.items enable row level security;

revoke all on public.items from anon, authenticated;
grant select on public.items to anon, authenticated;
grant insert (report_type, section, item_name, category, description, location,
              item_date, contact_info, image_url)
  on public.items to anon, authenticated;          -- new reports can't set status/illustration/id
grant update (status) on public.items to anon, authenticated;

create policy "Anyone can read reports"
  on public.items for select
  to anon, authenticated
  using (true);

create policy "Anyone can post a report"
  on public.items for insert
  to anon, authenticated
  with check (status = 'open' and returned_date is null);

create policy "Anyone can change a report's status"
  on public.items for update
  to anon, authenticated
  using (true)
  with check (true);                                  -- column grant limits this to `status`

-- -----------------------------------------------------------------------------
-- Admin: shared password (hashed) kept in a schema the API does not expose.
-- Default password: 12345 — change it with:
--   update private.admin_secret set password_hash = extensions.crypt('NEW', extensions.gen_salt('bf'));
-- -----------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.admin_secret (
  id            int primary key default 1 check (id = 1),
  password_hash text not null
);
insert into private.admin_secret (password_hash)
values (extensions.crypt('12345', extensions.gen_salt('bf')));

create or replace function private.is_admin(p_password text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.password_hash = extensions.crypt(coalesce(p_password, ''), s.password_hash)
       from private.admin_secret s where s.id = 1),
    false);
$$;

-- Entry-screen check: true when the admin password is right.
create or replace function public.admin_check(p_password text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin(p_password);
$$;

-- Admin edit. p_item keys: section, item_name, category, description, location, item_date,
-- contact_info, image_url, name_en, description_en (missing keys keep their value).
create or replace function public.admin_update_item(p_password text, p_id uuid, p_item jsonb)
returns public.items
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.items;
begin
  if not private.is_admin(p_password) then
    raise exception 'admin password required' using errcode = '28000';
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

create or replace function public.admin_delete_item(p_password text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin(p_password) then
    raise exception 'admin password required' using errcode = '28000';
  end if;
  delete from public.items where id = p_id;
end;
$$;

-- "Restore sample data": wipes all reports and reloads the demo items.
-- private.load_demo_items() is created by supabase/seed.sql.
create or replace function public.admin_reset_demo(p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin(p_password) then
    raise exception 'admin password required' using errcode = '28000';
  end if;
  delete from public.items where true;
  perform private.load_demo_items();
end;
$$;

revoke all on function private.is_admin(text) from public, anon, authenticated;
revoke all on function public.items_sync_returned_date() from public, anon, authenticated;
revoke all on function public.admin_check(text) from public;
revoke all on function public.admin_update_item(text, uuid, jsonb) from public;
revoke all on function public.admin_delete_item(text, uuid) from public;
revoke all on function public.admin_reset_demo(text) from public;
grant execute on function public.admin_check(text) to anon, authenticated;
grant execute on function public.admin_update_item(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.admin_delete_item(text, uuid) to anon, authenticated;
grant execute on function public.admin_reset_demo(text) to anon, authenticated;
