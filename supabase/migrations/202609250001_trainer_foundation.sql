-- Bootstrap the exact existing schema.sql contract if cloud workouts are not deployed.
-- Trainer reads/writes use narrow RPCs: existing workout owner policies stay intact.
begin;
do $setup$ begin
 if to_regclass('public.workouts') is null then
 execute $bootstrap$
-- SETKEEPのクラウド保存用テーブル
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

$bootstrap$;
 end if;
end $setup$;
create table public.trainer_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (length(trim(display_name)) between 1 and 80),
 created_at timestamptz not null default now()
);
create table public.trainer_invites (
 id uuid primary key default gen_random_uuid(),
 trainer_id uuid not null references public.trainer_profiles(user_id) on delete cascade,
 token uuid not null unique default gen_random_uuid(),
 expires_at timestamptz not null default now() + interval '24 hours',
 used_by uuid references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table public.trainer_client_links (
 id uuid primary key default gen_random_uuid(),
 trainer_id uuid not null references public.trainer_profiles(user_id) on delete cascade,
 client_id uuid not null references auth.users(id) on delete cascade,
 client_name text not null check (length(trim(client_name)) between 1 and 80),
 status text not null default 'active' check (status in ('active','revoked')),
 share_workouts boolean not null default true,
 allow_recording boolean not null default false,
 share_heatmap boolean not null default false,
 share_body_weight boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(trainer_id,client_id), check(trainer_id <> client_id)
);
create table public.trainer_notes (
 id uuid primary key default gen_random_uuid(),
 trainer_id uuid not null default auth.uid(),
 client_id uuid not null,
 body text not null check (length(trim(body)) between 1 and 10000),
 created_at timestamptz not null default now(),
 foreign key(trainer_id,client_id) references public.trainer_client_links(trainer_id,client_id) on delete cascade
);
create function public.trainer_valid_menu(items jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare item jsonb; total integer := 0;
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 100 then return false; end if;
 for item in select * from jsonb_array_elements(items) loop
  if jsonb_typeof(item) is distinct from 'object' or coalesce(length(item->>'exercise_id'),0)=0 or coalesce(length(item->>'exercise_name'),0)=0
   or coalesce((item->>'sets')::integer,0) not between 1 and 50
   or coalesce((item->>'target_reps')::integer,0) not between 1 and 1000
   or coalesce((item->>'target_weight')::numeric,-1) not between 0 and 2000 then return false; end if;
  total := total + (item->>'sets')::integer;
 end loop;
 return total <= 100;
exception when others then return false;
end $$;
create table public.trainer_menus (
 id uuid primary key default gen_random_uuid(),
 trainer_id uuid not null default auth.uid(),
 client_id uuid not null,
 name text not null check (length(trim(name)) between 1 and 120),
 note text not null default '' check(length(note) <= 10000),
 -- IDs refer to the shared code catalog, never a second exercise master.
 items jsonb not null check(public.trainer_valid_menu(items)),
 created_at timestamptz not null default now(),
 foreign key(trainer_id,client_id) references public.trainer_client_links(trainer_id,client_id) on delete cascade
);
alter table public.workouts add column recorded_by uuid references auth.users(id) on delete set null;
alter table public.workouts add column record_source text not null default 'self' check(record_source in ('self','trainer'));
create index trainer_links_client on public.trainer_client_links(client_id,status);
create index trainer_notes_owner on public.trainer_notes(trainer_id,client_id);
create index trainer_menus_owner on public.trainer_menus(trainer_id,client_id);
create index trainer_workout_history on public.workouts(user_id,performed_at desc);

alter table public.trainer_profiles enable row level security;
alter table public.trainer_invites enable row level security;
alter table public.trainer_client_links enable row level security;
alter table public.trainer_notes enable row level security;
alter table public.trainer_menus enable row level security;
revoke all on public.trainer_profiles,public.trainer_invites,public.trainer_client_links,public.trainer_notes,public.trainer_menus from public,anon,authenticated;
grant select,insert,update on public.trainer_profiles to authenticated;
grant select on public.trainer_client_links to authenticated;
grant select,insert,delete on public.trainer_notes,public.trainer_menus to authenticated;
create policy trainer_profile_owner on public.trainer_profiles for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy trainer_profile_linked_client on public.trainer_profiles for select to authenticated using(exists(select 1 from public.trainer_client_links l where l.trainer_id=trainer_profiles.user_id and l.client_id=auth.uid() and l.status='active'));
create policy trainer_link_participant on public.trainer_client_links for select to authenticated using(trainer_id=auth.uid() or client_id=auth.uid());
create policy trainer_notes_read on public.trainer_notes for select to authenticated using(trainer_id=auth.uid());
create policy trainer_notes_delete on public.trainer_notes for delete to authenticated using(trainer_id=auth.uid());
create policy trainer_notes_write on public.trainer_notes for insert to authenticated with check(trainer_id=auth.uid() and exists(select 1 from public.trainer_client_links l where l.trainer_id=auth.uid() and l.client_id=trainer_notes.client_id and l.status='active'));
create policy trainer_menus_read on public.trainer_menus for select to authenticated using(trainer_id=auth.uid());
create policy trainer_menus_delete on public.trainer_menus for delete to authenticated using(trainer_id=auth.uid());
create policy trainer_menus_write on public.trainer_menus for insert to authenticated with check(trainer_id=auth.uid() and exists(select 1 from public.trainer_client_links l where l.trainer_id=auth.uid() and l.client_id=trainer_menus.client_id and l.status='active'));

create function public.trainer_create_invite() returns uuid language plpgsql security definer set search_path='' as $$
declare t uuid;
begin
 if not exists(select 1 from public.trainer_profiles where user_id=auth.uid()) then raise exception 'Trainer profile required'; end if;
 -- One outstanding code per trainer; retry rotates rather than leaking old codes.
 delete from public.trainer_invites where trainer_id=auth.uid() and used_by is null;
 insert into public.trainer_invites(trainer_id) values(auth.uid()) returning token into t;
 return t;
end $$;
create function public.trainer_preview_invite(p_token uuid) returns text language sql stable security definer set search_path='' as $$
 select p.display_name from public.trainer_invites i join public.trainer_profiles p on p.user_id=i.trainer_id
 where auth.uid() is not null and i.token=p_token and i.expires_at>now() and i.used_by is null and i.trainer_id<>auth.uid();
$$;
create function public.trainer_accept_invite(p_token uuid,p_name text,p_recording boolean default false,p_heatmap boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.trainer_invites; result uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into i from public.trainer_invites where token=p_token for update;
 if i.id is null or i.expires_at<=now() or i.used_by is not null or i.trainer_id=auth.uid() then raise exception 'Invalid or expired invite'; end if;
 insert into public.trainer_client_links(trainer_id,client_id,client_name,share_workouts,allow_recording,share_heatmap)
 values(i.trainer_id,auth.uid(),p_name,true,p_recording,p_heatmap)
 on conflict(trainer_id,client_id) do update set client_name=excluded.client_name,status='active',share_workouts=true,allow_recording=excluded.allow_recording,share_heatmap=excluded.share_heatmap,share_body_weight=false,updated_at=now()
 returning id into result;
 update public.trainer_invites set used_by=auth.uid() where id=i.id;
 return result;
end $$;
create function public.trainer_revoke_link(p_link uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.trainer_client_links set status='revoked',share_workouts=false,allow_recording=false,share_heatmap=false,share_body_weight=false,updated_at=now()
 where id=p_link and (client_id=auth.uid() or trainer_id=auth.uid());
 if not found then raise exception 'Link not found'; end if;
end $$;
create function public.trainer_client_workouts(p_client uuid,p_offset integer default 0) returns table(id uuid,performed_at timestamptz,duration_seconds integer,gym_name text,sets jsonb,recorded_by uuid,record_source text) language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.trainer_client_links l where l.trainer_id=auth.uid() and l.client_id=p_client and l.status='active' and l.share_workouts) then raise exception 'Sharing not authorized'; end if;
 return query select w.id,w.performed_at,w.duration_seconds,w.gym_name,w.sets,w.recorded_by,w.record_source from public.workouts w where w.user_id=p_client order by w.performed_at desc,w.id limit 100 offset greatest(0,p_offset);
end $$;
create function public.trainer_record_workout(p_client uuid,p_request uuid,p_date timestamptz,p_sets jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 -- Lock the authorization row so revoke and record serialize.
 perform 1 from public.trainer_client_links l where l.trainer_id=auth.uid() and l.client_id=p_client and l.status='active' and l.allow_recording for share;
 if not found then raise exception 'Recording not authorized'; end if;
 if p_request is null or p_date is null or p_date>now()+interval '1 day' or jsonb_typeof(p_sets) is distinct from 'array' then raise exception 'Invalid workout'; end if;
 if jsonb_array_length(p_sets) not between 1 and 100 then raise exception 'Invalid sets'; end if;
 if exists(select 1 from jsonb_array_elements(p_sets) s where jsonb_typeof(s) is distinct from 'object' or coalesce(length(s->>'exerciseId'),0)=0 or coalesce(length(s->>'exerciseName'),0)=0 or s->>'recordType' not in ('weightReps','bodyweightReps','assistedReps') or (s->>'recordType') is null or coalesce((s->>'weight')::numeric,-1) not between 0 and 2000 or coalesce((s->>'reps')::integer,0) not between 1 and 1000 or (s->>'completed')::boolean is distinct from true) then raise exception 'Invalid set values'; end if;
 insert into public.workouts(user_id,client_id,performed_at,sets,recorded_by,record_source)
 values(p_client,'trainer:'||auth.uid()::text||':'||p_request::text,p_date,p_sets,auth.uid(),'trainer')
 on conflict(user_id,client_id) do nothing returning id into result;
 if result is null then select id into result from public.workouts where user_id=p_client and client_id='trainer:'||auth.uid()::text||':'||p_request::text; end if;
 return result;
end $$;
-- Only explicitly selected local records are published by the client. No weight data.
create function public.trainer_share_workout(p_date timestamptz,p_duration integer,p_gym text,p_sets jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.trainer_client_links where client_id=auth.uid() and status='active' and share_workouts for share;
 if not found then raise exception 'No active sharing link'; end if;
 if p_date is null or jsonb_typeof(p_sets) is distinct from 'array' or jsonb_array_length(p_sets) not between 1 and 1000 then raise exception 'Invalid workout'; end if;
 -- Match existing timestamp identity, including equivalent timezone spellings.
 if exists(select 1 from public.workouts where user_id=auth.uid() and performed_at=p_date and record_source='trainer') then return; end if;
 update public.workouts set sets=p_sets,duration_seconds=p_duration,gym_name=p_gym,updated_at=now() where user_id=auth.uid() and performed_at=p_date and record_source='self';
 if not found then
 insert into public.workouts(user_id,client_id,performed_at,duration_seconds,gym_name,sets,recorded_by)
 values(auth.uid(),p_date::text,p_date,p_duration,p_gym,p_sets,auth.uid());
 end if;
end $$;
-- Preserve recorder attribution even through existing owner upserts/updates.
create function public.trainer_guard_attribution() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('anon','authenticated') then
  if tg_op='INSERT' then new.recorded_by=auth.uid(); new.record_source='self';
  else new.recorded_by=old.recorded_by; new.record_source=old.record_source; end if;
 end if;
 return new;
end $$;
create trigger trainer_workout_attribution before insert or update on public.workouts for each row execute function public.trainer_guard_attribution();

revoke all on function public.trainer_create_invite(),public.trainer_preview_invite(uuid),public.trainer_accept_invite(uuid,text,boolean,boolean),public.trainer_revoke_link(uuid),public.trainer_client_workouts(uuid,integer),public.trainer_record_workout(uuid,uuid,timestamptz,jsonb),public.trainer_share_workout(timestamptz,integer,text,jsonb),public.trainer_guard_attribution() from public,anon,authenticated;
grant execute on function public.trainer_create_invite(),public.trainer_preview_invite(uuid),public.trainer_accept_invite(uuid,text,boolean,boolean),public.trainer_revoke_link(uuid),public.trainer_client_workouts(uuid,integer),public.trainer_record_workout(uuid,uuid,timestamptz,jsonb),public.trainer_share_workout(timestamptz,integer,text,jsonb) to authenticated;
commit;
