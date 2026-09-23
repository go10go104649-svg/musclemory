-- Public reference data is read-only; personal stores/reports are owner-only.
begin;
create extension if not exists pg_trgm with schema extensions;
create table if not exists public.gym_chains (
  id text primary key, name text not null, updated_at timestamptz not null default now()
);
create table if not exists public.gym_stores (
  id text primary key, chain_id text not null references public.gym_chains(id),
  source_id text not null, name text not null, prefecture text, city text,
  address text, station text, official_url text,
  equipment_status text not null default 'not_collected',
  active boolean not null default true, source jsonb not null default '{}',
  updated_at timestamptz not null default now(), unique(chain_id,source_id)
);
create table if not exists public.equipment (
  id text primary key, name text not null, normalized_name text not null,
  category text not null, load_type text, manufacturer text, model text,
  needs_review boolean not null default false,
  source jsonb not null default '{}', updated_at timestamptz not null default now()
);
create table if not exists public.gym_store_equipment (
  store_id text not null references public.gym_stores(id),
  equipment_id text not null references public.equipment(id),
  quantity integer check(quantity > 0), available boolean not null default true,
  raw_name text not null, source_url text, checked_at timestamptz,
  source jsonb not null default '{}', updated_at timestamptz not null default now(),
  primary key(store_id,equipment_id)
);
create table if not exists public.equipment_exercise_mapping (
  equipment_id text not null references public.equipment(id),
  exercise_id text not null check(length(exercise_id)>0),
  rationale text not null, primary key(equipment_id,exercise_id)
);
create table if not exists public.user_gym_stores (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  store_id text not null references public.gym_stores(id),
  created_at timestamptz not null default now(), primary key(user_id,store_id)
);
create table if not exists public.gym_equipment_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  store_id text not null references public.gym_stores(id),
  equipment_id text references public.equipment(id),
  kind text not null check(kind in ('not_present','removed','added','wrong_name','other')),
  equipment_name text check(length(equipment_name)<=200),
  comment text not null default '' check(length(comment)<=1000),
  status text not null default 'pending' check(status in ('pending','approved','rejected','resolved')),
  created_at timestamptz not null default now(),
  check(kind <> 'added' or coalesce(length(trim(equipment_name)),0)>0)
);
create index if not exists gym_stores_chain_idx on public.gym_stores(chain_id);
create index if not exists gym_stores_name_idx on public.gym_stores using gin (name extensions.gin_trgm_ops);
create index if not exists gym_stores_city_idx on public.gym_stores using gin (city extensions.gin_trgm_ops);
create index if not exists gym_stores_station_idx on public.gym_stores using gin (station extensions.gin_trgm_ops);
create index if not exists gym_equipment_reverse_idx on public.gym_store_equipment(equipment_id);
create index if not exists exercise_equipment_reverse_idx on public.equipment_exercise_mapping(exercise_id);
create index if not exists registered_store_reverse_idx on public.user_gym_stores(store_id);
create index if not exists reports_store_idx on public.gym_equipment_reports(store_id);
create index if not exists reports_equipment_idx on public.gym_equipment_reports(equipment_id);
create index if not exists reports_rate_idx on public.gym_equipment_reports(user_id,store_id,created_at desc);

alter table public.gym_chains enable row level security;
alter table public.gym_stores enable row level security;
alter table public.equipment enable row level security;
alter table public.gym_store_equipment enable row level security;
alter table public.equipment_exercise_mapping enable row level security;
alter table public.user_gym_stores enable row level security;
alter table public.gym_equipment_reports enable row level security;
revoke all on public.gym_chains, public.gym_stores, public.equipment, public.gym_store_equipment,
  public.equipment_exercise_mapping, public.user_gym_stores, public.gym_equipment_reports from anon, authenticated;
grant select on public.gym_chains, public.gym_stores, public.equipment, public.gym_store_equipment,
  public.equipment_exercise_mapping to anon, authenticated;
grant select,insert,delete on public.user_gym_stores to authenticated;
grant select on public.gym_equipment_reports to authenticated;
grant insert(store_id,equipment_id,kind,equipment_name,comment) on public.gym_equipment_reports to authenticated;
create policy gym_chains_read on public.gym_chains for select to anon,authenticated using(true);
create policy gym_stores_read on public.gym_stores for select to anon,authenticated using(true);
create policy equipment_read on public.equipment for select to anon,authenticated using(true);
create policy gym_store_equipment_read on public.gym_store_equipment for select to anon,authenticated using(true);
create policy equipment_mapping_read on public.equipment_exercise_mapping for select to anon,authenticated using(true);
create policy personal_stores_read on public.user_gym_stores for select to authenticated using(user_id=(select auth.uid()));
create policy personal_stores_insert on public.user_gym_stores for insert to authenticated with check(user_id=(select auth.uid()));
create policy personal_stores_delete on public.user_gym_stores for delete to authenticated using(user_id=(select auth.uid()));
create policy reports_read on public.gym_equipment_reports for select to authenticated using(user_id=(select auth.uid()));
create policy reports_insert on public.gym_equipment_reports for insert to authenticated with check(user_id=(select auth.uid()) and status='pending');

create or replace function public.limit_gym_equipment_reports() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
  if new.equipment_id is not null and not exists (
    select 1 from public.gym_store_equipment where store_id=new.store_id and equipment_id=new.equipment_id
  ) then raise exception 'Equipment does not belong to this store'; end if;
  if exists (select 1 from public.gym_equipment_reports r where r.user_id=new.user_id
    and r.store_id=new.store_id and r.equipment_id is not distinct from new.equipment_id
    and r.kind=new.kind and r.created_at>now()-interval '5 minutes')
  or (select count(*) from public.gym_equipment_reports where user_id=new.user_id and created_at>now()-interval '5 minutes')>=5
  then raise exception 'Please wait before reporting again' using errcode='P0001'; end if;
  return new;
end $$;
create trigger limit_gym_reports before insert on public.gym_equipment_reports
for each row execute function public.limit_gym_equipment_reports();
revoke all on function public.limit_gym_equipment_reports() from public;

create or replace function public.search_gym_stores(search_query text default '', page_offset integer default 0)
returns table(id text,chain_id text,chain_name text,name text,prefecture text,city text,address text,station text,equipment_status text)
language sql stable security invoker set search_path='' as $$
 select s.id,s.chain_id,c.name,s.name,s.prefecture,s.city,s.address,s.station,s.equipment_status
 from public.gym_stores s join public.gym_chains c on c.id=s.chain_id
 where s.active and (trim(search_query)='' or
   s.name ilike '%'||replace(replace(trim(search_query),'%','\%'),'_','\_')||'%' or
   s.city ilike '%'||replace(replace(trim(search_query),'%','\%'),'_','\_')||'%' or
   s.station ilike '%'||replace(replace(trim(search_query),'%','\%'),'_','\_')||'%')
 order by s.name,s.id limit 30 offset greatest(0,least(page_offset,100000));
$$;
revoke all on function public.search_gym_stores(text,integer) from public;
grant execute on function public.search_gym_stores(text,integer) to anon,authenticated;
commit;
