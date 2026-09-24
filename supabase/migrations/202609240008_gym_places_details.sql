begin;
-- Additive metadata: original categories/names, IDs and mappings remain intact.
alter table public.gym_stores add column if not exists checked_at timestamptz;
-- Copy an explicitly recorded source date, never infer it from import time.
update public.gym_stores set checked_at=(source->>'equipment_checked_at')::timestamp at time zone 'Asia/Tokyo'
 where checked_at is null and source->>'equipment_checked_at' ~ '^2026-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$';
alter table public.equipment add column if not exists display_name text;
alter table public.equipment add column if not exists aliases text[] not null default '{}';
alter table public.gym_store_equipment add column if not exists unavailable_quantity integer;
alter table public.gym_store_equipment add column if not exists source_kind text not null default 'official'
  check(source_kind in ('admin','official','confirmed_report','unconfirmed_report'));
alter table public.gym_store_equipment add constraint gym_unavailable_quantity_valid check(
  unavailable_quantity is null or (quantity is not null and unavailable_quantity between 0 and quantity));

create table public.gym_equipment_changes (
  id bigint generated always as identity primary key,
  store_id text not null, equipment_id text not null,
  operation text not null, before_data jsonb, after_data jsonb,
  changed_at timestamptz not null default now(),
  changed_by uuid default auth.uid()
);
alter table public.gym_equipment_changes enable row level security;
revoke all on public.gym_equipment_changes from anon, authenticated;
create function public.record_gym_equipment_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' and to_jsonb(old)=to_jsonb(new) then return new; end if;
  insert into public.gym_equipment_changes(store_id,equipment_id,operation,before_data,after_data)
  values(coalesce(new.store_id,old.store_id),coalesce(new.equipment_id,old.equipment_id),
    tg_op,case when tg_op<>'INSERT' then to_jsonb(old) end,
    case when tg_op<>'DELETE' then to_jsonb(new) end);
  return coalesce(new,old);
end $$;
revoke all on function public.record_gym_equipment_change() from public;
create trigger record_gym_equipment_change after insert or update or delete
on public.gym_store_equipment for each row execute function public.record_gym_equipment_change();
-- Lower-confidence sources cannot overwrite a reviewed row. Reports themselves
-- never write to the master; an administrator explicitly approves corrections.
create function public.protect_gym_equipment_source() returns trigger
language plpgsql set search_path='' as $$
declare ranks text[] := array['unconfirmed_report','confirmed_report','official','admin'];
begin
  if array_position(ranks,new.source_kind)<array_position(ranks,old.source_kind)
  then return old; end if;
  return new;
end $$;
revoke all on function public.protect_gym_equipment_source() from public;
create trigger protect_gym_equipment_source before update on public.gym_store_equipment
for each row execute function public.protect_gym_equipment_source();

alter table public.gym_equipment_reports drop constraint gym_equipment_reports_status_check;
alter table public.gym_equipment_reports add constraint gym_equipment_reports_status_check
 check(status in ('pending','reviewing','approved','rejected','resolved'));
create index gym_reports_open_idx on public.gym_equipment_reports(user_id,store_id,equipment_id)
 where status in ('pending','reviewing','approved');
create or replace function public.limit_gym_equipment_reports() returns trigger
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
 if new.equipment_id is not null and not exists (
  select 1 from public.gym_store_equipment where store_id=new.store_id and equipment_id=new.equipment_id
 ) then raise exception 'Equipment does not belong to this store'; end if;
 -- Return success without inserting another open report. Resolved/rejected
 -- reports do not suppress a later change, even inside the rate-limit window.
 if exists(select 1 from public.gym_equipment_reports r where r.user_id=new.user_id
  and r.store_id=new.store_id and r.equipment_id is not distinct from new.equipment_id
  and r.kind=new.kind and coalesce(trim(r.equipment_name),'')=coalesce(trim(new.equipment_name),'')
  and trim(r.comment)=trim(new.comment) and r.status in ('pending','reviewing','approved'))
 then return null; end if;
 if (select count(*) from public.gym_equipment_reports where user_id=new.user_id
  and created_at>now()-interval '5 minutes')>=5
 then raise exception 'Please wait before reporting again'; end if;
 return new;
end $$;

create function public.gym_search_text(value text) returns text language sql immutable
set search_path='' as $$ select regexp_replace(lower(normalize(coalesce(value,''),NFKC)), '\s+', '', 'g') $$;
create function public.search_gym_stores_v2(search_query text default '',page_offset integer default 0, selected_chain text default null)
returns setof jsonb language sql stable security invoker set search_path='' as $$
 with candidates as (
 select s.*,c.name as chain_name,
 public.gym_search_text(s.name) as sn, public.gym_search_text(c.name) as cn,
 public.gym_search_text(c.name||s.name) as full_name,
 array(select public.gym_search_text(a||s.name) from unnest(c.search_aliases) a) as aliases,
 public.gym_search_text(search_query) as q
 from public.gym_stores s join public.gym_chains c on c.id=s.chain_id
 where s.active and (selected_chain is null or s.chain_id=selected_chain)
 )
 select to_jsonb(x)-'sn'-'cn'-'full_name'-'aliases'-'q'
 from candidates x where q='' or strpos(full_name,q)>0 or exists(select 1 from unnest(aliases) a where strpos(a,q)>0)
 order by case when q=sn or q=cn or q=full_name then 0
  when starts_with(sn,q) or starts_with(cn,q) or starts_with(full_name,q) then 1 else 2 end,
 name,id limit 30 offset greatest(0,least(page_offset,100000))
$$;
-- Keep the old RPC signature for installed clients; apply the new search scope.
create or replace function public.search_gym_stores(search_query text default '',page_offset integer default 0)
returns table(id text,chain_id text,chain_name text,name text,prefecture text,city text,address text,station text,equipment_status text)
language sql stable security invoker set search_path='' as $$
 select j->>'id',j->>'chain_id',j->>'chain_name',j->>'name',j->>'prefecture',j->>'city',
 j->>'address',j->>'station',j->>'equipment_status'
 from public.search_gym_stores_v2(search_query,page_offset) j;
$$;
revoke all on function public.search_gym_stores_v2(text,integer,text) from public;
grant execute on function public.search_gym_stores_v2(text,integer,text) to anon,authenticated;
grant execute on function public.gym_search_text(text) to anon,authenticated;

create function public.gym_store_exercise_evidence(target_store_id text)
returns table(exercise_id text,equipment_ids text[],equipment_names text[],rule_id text)
language sql stable security invoker set search_path='' as $$
 with usable as (
  select g.equipment_id,coalesce(e.display_name,e.name) as name
  from public.gym_store_equipment g join public.equipment e on e.id=g.equipment_id
  where g.store_id=target_store_id and g.available
  and (g.quantity is null or g.quantity-coalesce(g.unavailable_quantity,0)>0)
 ),
 direct as (
 select m.exercise_id,array[u.equipment_id] as equipment_ids,array[u.name] as equipment_names,null::text as rule_id
 from usable u join public.equipment_exercise_mapping m on m.equipment_id=u.equipment_id
 ),
 combinations as (
 select r.exercise_id,array_agg(i.equipment_id order by i.equipment_id),
 array_agg(u.name order by i.equipment_id),r.id
 from public.exercise_equipment_rules r join public.exercise_equipment_rule_items i on i.rule_id=r.id
 left join usable u on u.equipment_id=i.equipment_id
 group by r.id,r.exercise_id having count(*)=count(u.equipment_id)
 )
 select * from direct union select * from combinations;
$$;
create or replace function public.gym_store_exercise_ids(target_store_id text)
returns table(exercise_id text) language sql stable security invoker set search_path='' as $$
 select distinct e.exercise_id from public.gym_store_exercise_evidence(target_store_id) e;
$$;
create function public.gym_store_detail(target_store_id text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'store',(select to_jsonb(s)||jsonb_build_object('chain_name',c.name) from public.gym_stores s
  join public.gym_chains c on c.id=s.chain_id where s.id=target_store_id),
 'equipment',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('equipment',
  to_jsonb(e)||jsonb_build_object(
    'equipment_exercise_mapping',coalesce((select jsonb_agg(jsonb_build_object('exercise_id',m.exercise_id))
      from public.equipment_exercise_mapping m where m.equipment_id=e.id),'[]'::jsonb),
    'exercise_equipment_rule_items',coalesce((select jsonb_agg(jsonb_build_object('rule_id',i.rule_id))
      from public.exercise_equipment_rule_items i where i.equipment_id=e.id),'[]'::jsonb)
  )) order by e.category,e.name,e.id)
  from public.gym_store_equipment g join public.equipment e on e.id=g.equipment_id where g.store_id=target_store_id),'[]'::jsonb),
 'evidence',coalesce((select jsonb_agg(to_jsonb(x)) from public.gym_store_exercise_evidence(target_store_id) x),'[]'::jsonb));
$$;
revoke all on function public.gym_store_exercise_evidence(text),public.gym_store_detail(text) from public;
grant execute on function public.gym_store_exercise_evidence(text),public.gym_store_detail(text) to anon,authenticated;
-- Explicit synonyms only; preserve original names and equipment identities.
update public.equipment set display_name='ハイロー',aliases=array['ハイロウ','プレートロードハイロウ','ハイロー']
 where name in ('ハイロウ','ハイロー','プレートロードハイロウ');
update public.equipment set aliases=array(
 select distinct a from unnest(aliases||array['シーテッドロー','シーテッドロウ','ローイング']) a)
 where name in ('シーテッドロー','シーテッドロウ','シーテッドケーブルロー','シーテッドケーブルロウ');
notify pgrst,'reload schema';
commit;
