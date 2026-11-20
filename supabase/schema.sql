-- Expense Manager — Supabase schema
-- Run in the Supabase SQL editor (or `supabase db push`).
--
-- Design notes
-- * Every table mirrors the local SQLite "content" columns 1:1 so the sync
--   engine can upsert rows without mapping.
-- * Primary key is (user_id, id): ids are generated on devices (UUIDs or
--   deterministic ids such as 'cat_food'), and are only unique per user.
-- * server_updated_at is assigned by the database (clock_timestamp) on every
--   insert/update. Clients pull "rows changed since my cursor" with it, so
--   device clock skew can never cause missed changes.
-- * Deletes are soft (deleted_at). Tombstones are kept so every device learns
--   about the deletion.
-- * Row Level Security isolates users: auth.uid() must equal user_id for
--   every read and write.

create or replace function public.touch_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

-- Helper to create a synced table with standard columns, RLS and trigger.
create or replace function public._em_setup_table(t text)
returns void language plpgsql as $$
begin
  execute format('alter table public.%I enable row level security', t);
  execute format('drop policy if exists "own rows select" on public.%I', t);
  execute format('drop policy if exists "own rows insert" on public.%I', t);
  execute format('drop policy if exists "own rows update" on public.%I', t);
  execute format('create policy "own rows select" on public.%I for select using (auth.uid() = user_id)', t);
  execute format('create policy "own rows insert" on public.%I for insert with check (auth.uid() = user_id)', t);
  execute format('create policy "own rows update" on public.%I for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
  -- No DELETE policy: clients soft-delete; hard deletes are not allowed.
  execute format('drop trigger if exists trg_touch on public.%I', t);
  execute format('create trigger trg_touch before insert or update on public.%I for each row execute function public.touch_server_updated_at()', t);
  execute format('create index if not exists %I on public.%I (user_id, server_updated_at, id)', t || '_pull_idx', t);
end;
$$;

create table if not exists public.accounts (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  name text not null,
  type text not null,
  currency text not null,
  icon text not null,
  color bigint not null,
  archived smallint not null default 0,
  primary key (user_id, id)
);

create table if not exists public.categories (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  name text not null,
  type text not null check (type in ('income', 'expense')),
  icon text not null,
  color bigint not null,
  is_custom smallint not null default 0,
  archived smallint not null default 0,
  sort_order integer not null default 0,
  primary key (user_id, id)
);

create table if not exists public.transactions (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  type text not null check (type in ('income', 'expense')),
  amount_minor bigint not null check (amount_minor > 0),
  category_id text not null,
  account_id text not null,
  note text not null default '',
  occurred_at bigint not null,
  recurring_rule_id text,
  is_favorite smallint not null default 0,
  primary key (user_id, id)
);

create table if not exists public.budgets (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  category_id text,
  amount_minor bigint not null,
  primary key (user_id, id)
);

create table if not exists public.goals (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  name text not null,
  target_minor bigint not null,
  saved_minor bigint not null default 0,
  target_date bigint,
  icon text not null,
  color bigint not null,
  primary key (user_id, id)
);

create table if not exists public.recurring_rules (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  server_updated_at timestamptz not null default clock_timestamp(),
  type text not null check (type in ('income', 'expense')),
  amount_minor bigint not null,
  category_id text not null,
  account_id text not null,
  note text not null default '',
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),
  start_at bigint not null,
  end_at bigint,
  occurrences_generated integer not null default 0,
  next_due_at bigint not null,
  active smallint not null default 1,
  primary key (user_id, id)
);

select public._em_setup_table(t)
from unnest(array['accounts', 'categories', 'transactions', 'budgets', 'goals', 'recurring_rules']) as t;
