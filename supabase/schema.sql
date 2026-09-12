-- MuscleMemoryのクラウド保存用テーブル
-- Supabase Dashboard > SQL Editor で実行してください。

create table if not exists public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  client_id text not null,
  performed_at timestamptz not null,
  duration_seconds integer not null default 0
    check (duration_seconds >= 0),
  gym_name text,
  note text not null default '',
  sets jsonb not null
    check (jsonb_typeof(sets) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_id)
);

alter table public.workouts add column if not exists note text not null default '';

alter table public.workouts enable row level security;

revoke all on table public.workouts from anon;
grant select, insert, update, delete on table public.workouts to authenticated;

drop policy if exists "Users can read their workouts" on public.workouts;
create policy "Users can read their workouts"
on public.workouts for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their workouts" on public.workouts;
create policy "Users can insert their workouts"
on public.workouts for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their workouts" on public.workouts;
create policy "Users can update their workouts"
on public.workouts for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their workouts" on public.workouts;
create policy "Users can delete their workouts"
on public.workouts for delete
to authenticated
using ((select auth.uid()) = user_id);
