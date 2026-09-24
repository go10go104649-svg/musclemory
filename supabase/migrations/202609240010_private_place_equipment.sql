begin;
-- A single evaluator for both public store inventories and private inventories.
create function public.equipment_exercise_evidence(selected_equipment_ids text[])
returns table(exercise_id text,equipment_ids text[],equipment_names text[],rule_id text)
language sql stable security invoker set search_path='' as $$
 with usable as (
 select e.id equipment_id,coalesce(e.display_name,e.name) name from public.equipment e
 where e.id=any(selected_equipment_ids)
 ), direct as (
 select m.exercise_id,array[u.equipment_id],array[u.name],null::text
 from usable u join public.equipment_exercise_mapping m on m.equipment_id=u.equipment_id
 ), combinations as (
 select r.exercise_id,array_agg(i.equipment_id order by i.equipment_id),
 array_agg(u.name order by i.equipment_id),r.id
 from public.exercise_equipment_rules r join public.exercise_equipment_rule_items i on i.rule_id=r.id
 left join usable u on u.equipment_id=i.equipment_id
 group by r.id,r.exercise_id having count(*)=count(u.equipment_id)
 ) select * from direct union select * from combinations;
$$;
create or replace function public.gym_store_exercise_evidence(target_store_id text)
returns table(exercise_id text,equipment_ids text[],equipment_names text[],rule_id text)
language sql stable security invoker set search_path='' as $$
 select * from public.equipment_exercise_evidence(array(
 select g.equipment_id from public.gym_store_equipment g
 where g.store_id=target_store_id and g.available
 and (g.quantity is null or g.quantity-coalesce(g.unavailable_quantity,0)>0)));
$$;
create function public.search_equipment(search_query text default '', page_offset integer default 0)
returns setof jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('equipment',to_jsonb(e)) from public.equipment e
 where public.gym_search_text(concat_ws(' ',e.name,e.display_name,e.manufacturer,e.model,array_to_string(e.aliases,' ')))
 like '%'||public.gym_search_text(search_query)||'%'
 order by e.name,e.id limit 30 offset greatest(page_offset,0);
$$;
revoke all on function public.equipment_exercise_evidence(text[]),public.search_equipment(text,integer) from public;
grant execute on function public.equipment_exercise_evidence(text[]),public.search_equipment(text,integer) to anon,authenticated;

create table public.user_custom_place_equipment (
 id text not null,
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 custom_place_id text not null,
 equipment_id text references public.equipment(id),
 name text not null check(length(trim(name)) between 1 and 120),
 quantity integer check(quantity between 1 and 999),
 exercise_ids text[] not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 primary key(user_id,custom_place_id,id),
 check(equipment_id is null or cardinality(exercise_ids)=0)
);
create unique index private_place_master_unique on public.user_custom_place_equipment(user_id,custom_place_id,equipment_id) where equipment_id is not null;
alter table public.user_custom_place_equipment enable row level security;
create policy private_equipment_owner on public.user_custom_place_equipment for all to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select,insert,update,delete on public.user_custom_place_equipment to authenticated;

create table public.gym_exercise_reports (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 store_id text not null references public.gym_stores(id),
 exercise_id text,
 report_kind text not null check(report_kind in ('missing_exercise','incorrect_exercise','other')),
 comment text not null default '' check(length(comment)<=2000),
 status text not null default 'pending' check(status in ('pending','reviewing','applied','rejected')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((report_kind='other' and length(trim(comment))>0) or
       (report_kind<>'other' and exercise_id is not null and length(trim(exercise_id))>0))
);
alter table public.gym_exercise_reports enable row level security;
create policy exercise_report_read on public.gym_exercise_reports for select to authenticated using(user_id=auth.uid());
create policy exercise_report_create on public.gym_exercise_reports for insert to authenticated with check(user_id=auth.uid() and status='pending');
grant select,insert on public.gym_exercise_reports to authenticated;
create unique index exercise_report_open_unique on public.gym_exercise_reports(user_id,store_id,exercise_id,report_kind) where status in ('pending','reviewing') and exercise_id is not null;
create index exercise_report_owner on public.gym_exercise_reports(user_id,created_at);
create function public.limit_gym_exercise_reports() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,10));
 if exists(select 1 from public.gym_exercise_reports r where r.user_id=new.user_id
 and r.store_id=new.store_id and r.exercise_id is not distinct from new.exercise_id
 and r.report_kind=new.report_kind and r.status in ('pending','reviewing')
 and (new.exercise_id is not null or (r.comment=new.comment and r.created_at>now()-interval '10 minutes')))
 then return null; end if;
 if (select count(*) from public.gym_exercise_reports where user_id=new.user_id and created_at>now()-interval '10 minutes')>=20
 then raise exception 'Please wait before reporting again'; end if;
 return new;
end; $$;
create trigger exercise_report_limit before insert on public.gym_exercise_reports for each row execute function public.limit_gym_exercise_reports();
commit;
