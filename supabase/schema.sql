-- Universal Notebook — Supabase schema
-- Run this in the Supabase SQL editor (or `supabase db push`) for a project.
--
-- Design: notes and folders are stored as rows of
--   { id, owner_id, revision, updated_at, data jsonb }
-- where `data` holds the exact map the Flutter app persists locally. This keeps
-- the on-device and cloud formats identical, so no field-by-field mapping is
-- needed. Row-Level Security scopes every row to its owner.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.notes (
  id          uuid primary key,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  revision    integer not null default 0,
  updated_at  timestamptz not null default now(),
  data        jsonb not null
);

create table if not exists public.folders (
  id          uuid primary key,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  updated_at  timestamptz not null default now(),
  data        jsonb not null
);

create table if not exists public.templates (
  id          uuid primary key,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  updated_at  timestamptz not null default now(),
  data        jsonb not null
);

create index if not exists notes_owner_idx     on public.notes (owner_id);
create index if not exists folders_owner_idx   on public.folders (owner_id);
create index if not exists templates_owner_idx on public.templates (owner_id);

-- ---------------------------------------------------------------------------
-- Row-Level Security: an authenticated user may only touch their own rows.
-- ---------------------------------------------------------------------------

alter table public.notes     enable row level security;
alter table public.folders   enable row level security;
alter table public.templates enable row level security;

do $$
begin
  -- notes
  if not exists (select 1 from pg_policies where policyname = 'notes_owner_all') then
    create policy notes_owner_all on public.notes
      for all
      using (auth.uid() = owner_id)
      with check (auth.uid() = owner_id);
  end if;

  -- folders
  if not exists (select 1 from pg_policies where policyname = 'folders_owner_all') then
    create policy folders_owner_all on public.folders
      for all
      using (auth.uid() = owner_id)
      with check (auth.uid() = owner_id);
  end if;

  -- templates
  if not exists (select 1 from pg_policies where policyname = 'templates_owner_all') then
    create policy templates_owner_all on public.templates
      for all
      using (auth.uid() = owner_id)
      with check (auth.uid() = owner_id);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Realtime: stream row changes so other signed-in devices pull within a second
-- or two instead of waiting for the periodic check. RLS still applies to what
-- each client receives. Safe to re-run.
-- ---------------------------------------------------------------------------

do $$
begin
  begin
    alter publication supabase_realtime add table public.notes;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.folders;
  exception when duplicate_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Account deletion: lets a signed-in user delete their own auth account
-- (and, via ON DELETE CASCADE above, all of their rows). Called by the app's
-- "Delete account and data" action through AuthService.deleteCurrentAccount().
-- ---------------------------------------------------------------------------

create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_current_user() from public, anon;
grant execute on function public.delete_current_user() to authenticated;
