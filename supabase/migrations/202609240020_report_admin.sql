begin;
create table public.app_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'admin' check(role='admin'),
 created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
revoke all on public.app_admins from anon,authenticated;
create function public.is_report_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.app_admins where user_id=(select auth.uid()) and role='admin');
$$;
revoke all on function public.is_report_admin() from public;
grant execute on function public.is_report_admin() to authenticated;

alter table public.gym_equipment_reports drop constraint gym_equipment_reports_status_check;
update public.gym_equipment_reports set status=case status when 'approved' then 'reviewing' when 'resolved' then 'applied' else status end;
alter table public.gym_equipment_reports add constraint gym_equipment_reports_status_check check(status in ('pending','reviewing','applied','rejected'));

alter table public.gym_exercise_reports add column admin_note text not null default '' check(length(admin_note)<=4000), add column reviewed_at timestamptz, add column reviewed_by uuid references auth.users(id) on delete set null;
alter table public.gym_equipment_reports add column admin_note text not null default '' check(length(admin_note)<=4000), add column reviewed_at timestamptz, add column reviewed_by uuid references auth.users(id) on delete set null;
create policy exercise_admin_read on public.gym_exercise_reports for select to authenticated using(public.is_report_admin());
create policy exercise_admin_update on public.gym_exercise_reports for update to authenticated using(public.is_report_admin()) with check(public.is_report_admin());
create policy equipment_admin_read on public.gym_equipment_reports for select to authenticated using(public.is_report_admin());
create policy equipment_admin_update on public.gym_equipment_reports for update to authenticated using(public.is_report_admin()) with check(public.is_report_admin());
grant update(status,admin_note) on public.gym_exercise_reports, public.gym_equipment_reports to authenticated;
-- Restrict new report inserts to user-owned fields, including after future schema additions.
revoke insert on public.gym_exercise_reports from authenticated;
grant insert(store_id,exercise_id,report_kind,comment) on public.gym_exercise_reports to authenticated;
create function public.review_report_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if new.status<>old.status and not ((old.status='pending' and new.status in ('reviewing','rejected')) or (old.status='reviewing' and new.status in ('applied','rejected'))) then raise exception 'Invalid report transition'; end if;
 if new.status='rejected' and length(trim(new.admin_note))=0 then raise exception 'Rejection note required'; end if;
 new.reviewed_by=auth.uid(); new.reviewed_at=now();
 return new;
end; $$;
create trigger exercise_review_guard before update on public.gym_exercise_reports for each row execute function public.review_report_guard();
create trigger equipment_review_guard before update on public.gym_equipment_reports for each row execute function public.review_report_guard();
create index exercise_admin_queue on public.gym_exercise_reports(status,created_at desc);
create index equipment_admin_queue on public.gym_equipment_reports(status,created_at desc);
create view public.admin_reports with (security_invoker=true) as
 select 'exercise'::text as report_type,r.id,r.store_id,concat_ws(' ',c.name,s.name) as store_name,r.exercise_id as target_id,null::text as equipment_name,null::text as entered_name,r.report_kind,r.comment,r.status,r.created_at,r.admin_note,r.reviewed_at,r.reviewed_by
 from public.gym_exercise_reports r join public.gym_stores s on s.id=r.store_id join public.gym_chains c on c.id=s.chain_id
 union all
 select 'equipment',r.id,r.store_id,concat_ws(' ',c.name,s.name),r.equipment_id,e.name,r.equipment_name,r.kind,r.comment,r.status,r.created_at,r.admin_note,r.reviewed_at,r.reviewed_by
 from public.gym_equipment_reports r join public.gym_stores s on s.id=r.store_id join public.gym_chains c on c.id=s.chain_id left join public.equipment e on e.id=r.equipment_id;
grant select on public.admin_reports to authenticated;
create function public.list_admin_reports(report_type_filter text, status_filter text default 'pending', search_text text default '', exercise_ids text[] default '{}', page_offset integer default 0)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 select jsonb_build_object('counts',(select jsonb_object_agg(status,n) from (select status,count(*) n from public.admin_reports where report_type=report_type_filter group by status) c),
 'rows',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from (
 select * from public.admin_reports where report_type=report_type_filter and (status_filter is null or status=status_filter)
 and (search_text='' or position(lower(search_text) in lower(store_name))>0 or position(lower(search_text) in lower(coalesce(equipment_name,'')||' '||coalesce(entered_name,'')))>0 or target_id=any(exercise_ids))
 order by created_at desc,id limit 50 offset greatest(page_offset,0)) r)) into result;
 return result;
end; $$;
revoke all on function public.list_admin_reports(text,text,text,text[],integer) from public;
grant execute on function public.list_admin_reports(text,text,text,text[],integer) to authenticated;
create function public.update_admin_report(report_type_value text,report_id uuid,expected_status text,new_status text,note text) returns void language plpgsql security invoker set search_path='' as $$
declare changed integer;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
 if report_type_value='exercise' then
 update public.gym_exercise_reports set status=new_status,admin_note=note where id=report_id and status=expected_status;
 elsif report_type_value='equipment' then
 update public.gym_equipment_reports set status=new_status,admin_note=note where id=report_id and status=expected_status;
 else raise exception 'Unknown report type'; end if;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'Report changed; reload required'; end if;
end; $$;
revoke all on function public.update_admin_report(text,uuid,text,text,text) from public;
grant execute on function public.update_admin_report(text,uuid,text,text,text) to authenticated;
commit;
