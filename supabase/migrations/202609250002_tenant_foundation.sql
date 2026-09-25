-- Additive tenant migration. 202609250001 and all legacy rows remain intact.
begin;
create table public.tenants (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 120),
 kind text not null default 'personal' check(kind in ('personal','gym','store','company')),
 billing_owner_id uuid not null references auth.users(id), legacy_trainer_id uuid unique references auth.users(id),
 created_at timestamptz not null default now()
);
create table public.tenant_memberships (
 tenant_id uuid not null references public.tenants(id), user_id uuid not null references auth.users(id),
 is_admin boolean not null default false, is_trainer boolean not null default false,
 status text not null default 'active' check(status in ('active','removed')),
 primary key(tenant_id,user_id)
);
create table public.tenant_subscriptions (
 tenant_id uuid primary key references public.tenants(id),
 status text not null default 'pending_setup' check(status in ('pending_setup','trialing','active','past_due','canceled')),
 plan text not null default 'trainer' check(plan in ('trainer','business')),
 stripe_customer_id text unique, stripe_subscription_id text unique,
 payment_method_ready boolean not null default false, trial_used_at timestamptz, trial_ends_at timestamptz,
 base_price_jpy integer not null default 3980 check(base_price_jpy=3980), included_trainers integer not null default 5 check(included_trainers=5),
 extra_trainer_price_jpy integer not null default 500 check(extra_trainer_price_jpy=500), updated_at timestamptz not null default now(),
 check(status <> 'trialing' or (payment_method_ready and trial_used_at is not null and trial_ends_at=trial_used_at+interval '14 days'))
);
create table public.tenant_clients (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
 linked_user_id uuid references auth.users(id), client_name text not null check(length(trim(client_name)) between 1 and 80),
 legacy_link_id uuid unique references public.trainer_client_links(id),
 status text not null default 'active' check(status in ('active','revoked')),
 share_workouts boolean not null default false, allow_recording boolean not null default false,
 share_heatmap boolean not null default false, share_body_weight boolean not null default false,
 consent_at timestamptz, created_at timestamptz not null default now(), unique(tenant_id,id), unique(tenant_id,linked_user_id)
);
create table public.tenant_assignments (
 tenant_id uuid not null, client_id uuid not null, user_id uuid not null,
 primary key(tenant_id,client_id,user_id),
 foreign key(tenant_id,client_id) references public.tenant_clients(tenant_id,id),
 foreign key(tenant_id,user_id) references public.tenant_memberships(tenant_id,user_id)
);
create table public.tenant_menus (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null,
 name text not null check(length(trim(name)) between 1 and 120), note text not null default '' check(length(note)<=10000),
 schedule text not null default 'single' check(schedule in ('single','repeat')), due_at timestamptz,
 status text not null default 'planned' check(status in ('planned','completed','canceled')),
 before_cancel_status text check(before_cancel_status in ('planned','completed')),
 created_by uuid not null references auth.users(id), edited_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1,
 unique(tenant_id,id), foreign key(tenant_id,client_id) references public.tenant_clients(tenant_id,id)
);
create table public.tenant_menu_exercises (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, menu_id uuid not null, position integer not null,
 exercise_id text not null, exercise_name text not null, body_part text not null, equipment text not null, record_type text not null,
 unique(tenant_id,id), unique(menu_id,position), foreign key(tenant_id,menu_id) references public.tenant_menus(tenant_id,id) on delete cascade
);
create table public.tenant_menu_sets (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, exercise_id uuid not null, position integer not null,
 values jsonb not null check(jsonb_typeof(values)='object'), unique(exercise_id,position),
 foreign key(tenant_id,exercise_id) references public.tenant_menu_exercises(tenant_id,id) on delete cascade
);
create table public.tenant_comments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null, client_id uuid not null,
 menu_id uuid, workout_date date, body text not null check(length(trim(body)) between 1 and 10000),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 foreign key(tenant_id,client_id) references public.tenant_clients(tenant_id,id),
 foreign key(tenant_id,menu_id) references public.tenant_menus(tenant_id,id)
);
create table public.tenant_templates (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id), name text not null check(length(trim(name)) between 1 and 120),
 items jsonb not null check(jsonb_typeof(items)='array'), created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.tenant_invites (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id),
 token uuid unique not null default gen_random_uuid(), kind text not null check(kind in ('staff','client')),
 client_id uuid, created_by uuid not null references auth.users(id), invited_email text,
 is_admin boolean not null default false, is_trainer boolean not null default true,
 expires_at timestamptz not null default now()+interval '24 hours', used_by uuid references auth.users(id),
 foreign key(tenant_id,client_id) references public.tenant_clients(tenant_id,id), check(kind <> 'staff' or invited_email is not null)
);
create table public.tenant_audit (
 id bigint generated always as identity primary key, tenant_id uuid not null references public.tenants(id), actor_id uuid,
 action text not null, entity_id text, before_data jsonb, after_data jsonb, created_at timestamptz not null default now()
);
-- Workout ownership policies are not broadened. Offline records remain inaccessible through owner RLS until verified linking.
alter table public.workouts alter column user_id drop not null;
alter table public.workouts add column tenant_id uuid references public.tenants(id), add column tenant_client_id uuid,
 add column canceled_at timestamptz, add column canceled_by uuid references auth.users(id),
 add constraint workout_tenant_client foreign key(tenant_id,tenant_client_id) references public.tenant_clients(tenant_id,id),
 add constraint workout_has_owner check(user_id is not null or (tenant_id is not null and tenant_client_id is not null)),
 add constraint workout_tenant_request unique(tenant_id,client_id);

create function public.tenant_has_role(t uuid, r text default 'member') returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tenant_memberships m where m.tenant_id=t and m.user_id=auth.uid() and m.status='active'
 and case r when 'admin' then m.is_admin when 'trainer' then m.is_trainer when 'owner' then exists(select 1 from public.tenants x where x.id=t and x.billing_owner_id=m.user_id) when 'member' then true else false end)
$$;
create function public.tenant_can_coach(t uuid,c uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.tenant_has_role(t,'trainer') and exists(select 1 from public.tenant_assignments a join public.tenant_clients c on c.tenant_id=a.tenant_id and c.id=a.client_id where a.tenant_id=t and a.client_id=$2 and a.user_id=auth.uid() and c.status='active')
$$;
create function public.tenant_audit_change() returns trigger language plpgsql security definer set search_path='' as $$
declare b jsonb; a jsonb; t uuid;
begin
 if tg_op <> 'INSERT' then b=to_jsonb(old); end if;
 if tg_op <> 'DELETE' then a=to_jsonb(new); end if;
 t=coalesce((a->>'tenant_id')::uuid,(b->>'tenant_id')::uuid);
 if tg_table_name='tenants' then t=coalesce((a->>'id')::uuid,(b->>'id')::uuid); end if;
 if t is not null then insert into public.tenant_audit(tenant_id,actor_id,action,entity_id,before_data,after_data)
 values(t,auth.uid(),tg_table_name||'.'||lower(tg_op),coalesce(a->>'id',b->>'id',a->>'user_id',b->>'user_id'),b,a); end if;
 return coalesce(new,old);
end $$;
-- Deterministic IDs keep each trainer separate; no inference from shared clients.
insert into public.tenants(id,name,billing_owner_id,legacy_trainer_id)
 select md5('setkeep.personal.'||user_id::text)::uuid,display_name,user_id,user_id from public.trainer_profiles;
insert into public.tenant_memberships select id,billing_owner_id,true,true,'active' from public.tenants;
insert into public.tenant_subscriptions(tenant_id) select id from public.tenants;
insert into public.tenant_clients(id,tenant_id,linked_user_id,client_name,legacy_link_id,status,share_workouts,allow_recording,share_heatmap,share_body_weight,consent_at,created_at)
 select l.id,t.id,l.client_id,l.client_name,l.id,l.status,l.share_workouts,l.allow_recording,l.share_heatmap,l.share_body_weight,l.updated_at,l.created_at
 from public.trainer_client_links l join public.tenants t on t.legacy_trainer_id=l.trainer_id;
insert into public.tenant_assignments select c.tenant_id,c.id,t.billing_owner_id from public.tenant_clients c join public.tenants t on t.id=c.tenant_id;
insert into public.tenant_menus(id,tenant_id,client_id,name,note,created_by,edited_by,created_at)
 select m.id,c.tenant_id,c.id,m.name,m.note,m.trainer_id,m.trainer_id,m.created_at from public.trainer_menus m join public.trainer_client_links l on l.trainer_id=m.trainer_id and l.client_id=m.client_id join public.tenant_clients c on c.legacy_link_id=l.id;
insert into public.tenant_menu_exercises(id,tenant_id,menu_id,position,exercise_id,exercise_name,body_part,equipment,record_type)
 select md5(m.id::text||'.'||i.n::text)::uuid,n.tenant_id,m.id,i.n::int,i.v->>'exercise_id',i.v->>'exercise_name',coalesce(i.v->>'body_part',''),coalesce(i.v->>'equipment',''),i.v->>'record_type'
 from public.trainer_menus m join public.tenant_menus n on n.id=m.id cross join lateral jsonb_array_elements(m.items) with ordinality i(v,n);
insert into public.tenant_menu_sets(tenant_id,exercise_id,position,values)
 select e.tenant_id,e.id,s,jsonb_build_object('weight',(i.v->>'target_weight')::numeric,'reps',(i.v->>'target_reps')::int)
 from public.trainer_menus m cross join lateral jsonb_array_elements(m.items) with ordinality i(v,n) join public.tenant_menu_exercises e on e.id=md5(m.id::text||'.'||i.n::text)::uuid cross join lateral generate_series(1,(i.v->>'sets')::int) s;
insert into public.tenant_comments(id,tenant_id,client_id,body,created_by,created_at)
 select n.id,c.tenant_id,c.id,n.body,n.trainer_id,n.created_at from public.trainer_notes n join public.trainer_client_links l on l.trainer_id=n.trainer_id and l.client_id=n.client_id join public.tenant_clients c on c.legacy_link_id=l.id;
update public.workouts w set tenant_id=c.tenant_id,tenant_client_id=c.id from public.tenant_clients c join public.tenants t on t.id=c.tenant_id where w.record_source='trainer' and w.recorded_by=t.legacy_trainer_id and w.user_id=c.linked_user_id;
insert into public.tenant_invites(id,tenant_id,token,kind,created_by,expires_at,used_by)
 select i.id,t.id,i.token,'client',i.trainer_id,i.expires_at,i.used_by from public.trainer_invites i join public.tenants t on t.legacy_trainer_id=i.trainer_id;
insert into public.tenant_audit(tenant_id,action,after_data) select id,'legacy.backfill',jsonb_build_object('legacy_trainer_id',legacy_trainer_id) from public.tenants;

-- No direct writes: RPCs serialize role, consent and assignment changes using the tenant row.
do $$ declare n text; begin
 foreach n in array array['tenants','tenant_memberships','tenant_subscriptions','tenant_clients','tenant_assignments','tenant_menus','tenant_menu_exercises','tenant_menu_sets','tenant_comments','tenant_templates','tenant_invites','tenant_audit'] loop
 execute format('alter table public.%I enable row level security',n);
 execute format('revoke all on public.%I from public,anon,authenticated',n);
 execute format('grant select on public.%I to authenticated',n);
 if n <> 'tenant_audit' then execute format('create trigger audit_change after insert or update or delete on public.%I for each row execute function public.tenant_audit_change()',n); end if;
 end loop;
end $$;
create policy tenant_read on public.tenants for select to authenticated using(public.tenant_has_role(id));
create policy members_read on public.tenant_memberships for select to authenticated using(public.tenant_has_role(tenant_id));
create policy billing_read on public.tenant_subscriptions for select to authenticated using(public.tenant_has_role(tenant_id,'owner'));
create policy clients_read on public.tenant_clients for select to authenticated using(public.tenant_can_coach(tenant_id,id) or public.tenant_has_role(tenant_id,'admin') or linked_user_id=auth.uid());
create policy assignment_read on public.tenant_assignments for select to authenticated using(public.tenant_has_role(tenant_id,'admin') or public.tenant_can_coach(tenant_id,client_id));
create policy menu_read on public.tenant_menus for select to authenticated using(public.tenant_can_coach(tenant_id,client_id));
create policy exercise_read on public.tenant_menu_exercises for select to authenticated using(exists(select 1 from public.tenant_menus m where m.id=tenant_menu_exercises.menu_id and m.tenant_id=tenant_menu_exercises.tenant_id));
create policy sets_read on public.tenant_menu_sets for select to authenticated using(exists(select 1 from public.tenant_menu_exercises e where e.id=tenant_menu_sets.exercise_id and e.tenant_id=tenant_menu_sets.tenant_id));
create policy comments_read on public.tenant_comments for select to authenticated using(public.tenant_can_coach(tenant_id,client_id));
create policy templates_read on public.tenant_templates for select to authenticated using(public.tenant_has_role(tenant_id,'trainer'));
-- Full audit snapshots contain coaching data: owners/admins must not read them by virtue of administration.
create policy audit_read on public.tenant_audit for select to authenticated using(public.tenant_has_role(tenant_id,'owner') and action ~ '^(tenants|tenant_memberships|tenant_subscriptions|tenant_assignments|tenant_invites)\.(insert|update|delete)$');
create trigger tenant_workout_audit after insert or update on public.workouts for each row execute function public.tenant_audit_change();

create function public.tenant_create(p_name text,p_kind text default 'personal') returns uuid language plpgsql security definer set search_path='' as $$
declare t uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.tenants(name,kind,billing_owner_id) values(p_name,p_kind,auth.uid()) returning id into t;
 insert into public.tenant_memberships values(t,auth.uid(),true,true,'active');
 insert into public.tenant_subscriptions(tenant_id) values(t);
 return t;
end $$;
create function public.tenant_billing_summary(p_tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare n int; s public.tenant_subscriptions;
begin
 if not public.tenant_has_role(p_tenant,'owner') then raise exception 'Billing owner required'; end if;
 select count(*) into n from public.tenant_memberships where tenant_id=p_tenant and status='active' and is_trainer;
 select * into s from public.tenant_subscriptions where tenant_id=p_tenant;
 return to_jsonb(s)||jsonb_build_object('active_trainers',n,'monthly_jpy',3980+greatest(n-5,0)*500);
end $$;
create function public.tenant_mutate(p_tenant uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid=(p_data->>'client_id')::uuid; u uuid=(p_data->>'user_id')::uuid; r uuid; m public.tenant_menus; x jsonb; v jsonb; e uuid; i int=0; j int; count_sets int=0; sub public.tenant_subscriptions;
begin
 perform 1 from public.tenants where id=p_tenant for update;
 if not found or not public.tenant_has_role(p_tenant) then raise exception 'Active tenant membership required'; end if;
 if p_action in ('client','assign','unassign','staff_invite','member') and not public.tenant_has_role(p_tenant,'admin') then raise exception 'Admin required'; end if;
 if p_action='client' then
 insert into public.tenant_clients(tenant_id,client_name) values(p_tenant,p_data->>'name') returning id into r;
 if public.tenant_has_role(p_tenant,'trainer') then insert into public.tenant_assignments values(p_tenant,r,auth.uid()); end if;
 elsif p_action in ('assign','unassign') then
 if not exists(select 1 from public.tenant_clients where tenant_id=p_tenant and id=c) or not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant and user_id=u and status='active' and is_trainer) then raise exception 'Invalid assignment'; end if;
 if p_action='assign' then insert into public.tenant_assignments values(p_tenant,c,u) on conflict do nothing;
 else delete from public.tenant_assignments where tenant_id=p_tenant and client_id=c and user_id=u; end if;
 elsif p_action='member' then
 if exists(select 1 from public.tenants where id=p_tenant and billing_owner_id=u) and p_data->>'status'='removed' then raise exception 'Transfer billing ownership first'; end if;
 select * into sub from public.tenant_subscriptions where tenant_id=p_tenant;
 if sub.status='trialing' and coalesce((p_data->>'trainer')::boolean,false) and p_data->>'status'='active' and (select count(*) from public.tenant_memberships where tenant_id=p_tenant and status='active' and is_trainer and user_id<>u)>=5 then raise exception 'Trial allows five trainer IDs'; end if;
 update public.tenant_memberships set is_admin=(p_data->>'admin')::boolean,is_trainer=(p_data->>'trainer')::boolean,status=p_data->>'status' where tenant_id=p_tenant and user_id=u;
 if not found then raise exception 'Member not found'; end if;
 if p_data->>'status'='removed' or not (p_data->>'trainer')::boolean then delete from public.tenant_assignments where tenant_id=p_tenant and user_id=u; end if;
 elsif p_action='owner' then
 if not public.tenant_has_role(p_tenant,'owner') or not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant and user_id=u and status='active') then raise exception 'Active member and billing owner required'; end if;
 update public.tenants set billing_owner_id=u where id=p_tenant;
 elsif p_action in ('staff_invite','client_invite') then
 if p_action='client_invite' and not (public.tenant_can_coach(p_tenant,c) or (c is null and public.tenant_has_role(p_tenant,'trainer'))) then raise exception 'Assigned trainer required'; end if;
 if p_action='staff_invite' and not (coalesce((p_data->>'admin')::boolean,false) or coalesce((p_data->>'trainer')::boolean,false)) then raise exception 'Staff role required'; end if;
 -- Reissuing invalidates outstanding invitations in exactly this scope.
 update public.tenant_invites set expires_at=now() where tenant_id=p_tenant and used_by is null and kind=case when p_action='staff_invite' then 'staff' else 'client' end and created_by=auth.uid() and client_id is not distinct from c and invited_email is not distinct from lower(p_data->>'email');
 insert into public.tenant_invites(tenant_id,kind,client_id,created_by,invited_email,is_admin,is_trainer)
 values(p_tenant,case when p_action='staff_invite' then 'staff' else 'client' end,c,auth.uid(),lower(p_data->>'email'),coalesce((p_data->>'admin')::boolean,false),coalesce((p_data->>'trainer')::boolean,true)) returning token into r;
 elsif p_action='comment' then
 if not public.tenant_can_coach(p_tenant,c) then raise exception 'Assigned trainer required'; end if;
 if p_data->>'menu_id' is not null and not exists(select 1 from public.tenant_menus where tenant_id=p_tenant and client_id=c and id=(p_data->>'menu_id')::uuid) then raise exception 'Menu/client mismatch'; end if;
 insert into public.tenant_comments(tenant_id,client_id,menu_id,workout_date,body,created_by) values(p_tenant,c,(p_data->>'menu_id')::uuid,(p_data->>'date')::date,p_data->>'body',auth.uid()) returning id into r;
 elsif p_action='template' then
 if not public.tenant_has_role(p_tenant,'trainer') then raise exception 'Trainer required'; end if;
 if not public.tenant_valid_items(p_data->'items') then raise exception 'Invalid template'; end if;
 insert into public.tenant_templates(tenant_id,name,items,created_by) values(p_tenant,p_data->>'name',p_data->'items',auth.uid()) returning id into r;
 elsif p_action in ('menu','menu_status') then
 if not public.tenant_can_coach(p_tenant,c) then raise exception 'Assigned trainer required'; end if;
 if p_data->>'id' is not null then
 select * into m from public.tenant_menus where tenant_id=p_tenant and client_id=c and id=(p_data->>'id')::uuid for update;
 if not found or m.version is distinct from (p_data->>'version')::int then raise exception 'Menu changed; reload before editing'; end if;
 if p_action='menu_status' then
 if p_data->>'status' is null or p_data->>'status' not in ('planned','completed','canceled') then raise exception 'Invalid status'; end if;
 if m.status='completed' and p_data->>'status'='planned' then raise exception 'Completed menus cannot be reopened for editing'; end if;
 update public.tenant_menus set before_cancel_status=case when p_data->>'status'='canceled' then m.status else null end, status=case when m.status='canceled' then coalesce(m.before_cancel_status,'planned') else p_data->>'status' end,edited_by=auth.uid(),updated_at=now(),version=version+1 where id=m.id;
 return jsonb_build_object('id',m.id);
 end if;
 if m.status<>'planned' then raise exception 'Only unperformed menus can be edited'; end if;
 r=m.id;
 update public.tenant_menus set name=p_data->>'name',note=coalesce(p_data->>'note',''),schedule=p_data->>'schedule',due_at=(p_data->>'due_at')::timestamptz,edited_by=auth.uid(),updated_at=now(),version=version+1 where id=r;
 delete from public.tenant_menu_exercises where menu_id=r;
 else
 if p_action='menu_status' then raise exception 'Menu ID required'; end if;
 insert into public.tenant_menus(tenant_id,client_id,name,note,schedule,due_at,created_by,edited_by) values(p_tenant,c,p_data->>'name',coalesce(p_data->>'note',''),coalesce(p_data->>'schedule','single'),(p_data->>'due_at')::timestamptz,auth.uid(),auth.uid()) returning id into r;
 end if;
 if not public.tenant_valid_items(p_data->'items') then raise exception 'Invalid menu items'; end if;
 for x in select * from jsonb_array_elements(p_data->'items') loop
 i=i+1;
 insert into public.tenant_menu_exercises(tenant_id,menu_id,position,exercise_id,exercise_name,body_part,equipment,record_type) values(p_tenant,r,i,x->>'exercise_id',x->>'exercise_name',coalesce(x->>'body_part',''),coalesce(x->>'equipment',''),x->>'record_type') returning id into e;
 j=0;
 for v in select * from jsonb_array_elements(x->'set_values') loop
 j=j+1; count_sets=count_sets+1;
 insert into public.tenant_menu_sets(tenant_id,exercise_id,position,values) values(p_tenant,e,j,v);
 end loop;
 end loop;
 else raise exception 'Unknown action'; end if;
 return jsonb_build_object('id',r);
end $$;
create function public.tenant_valid_items(items jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare x jsonb; s jsonb; n int=0;
begin
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 100 then return false; end if;
 for x in select * from jsonb_array_elements(items) loop
 if coalesce(length(x->>'exercise_id'),0)=0 or coalesce(length(x->>'exercise_name'),0)=0 or x->>'record_type' is null or x->>'record_type' not in ('weightReps','bodyweightReps','assistedReps','timed','cardio','distance','loadedDistance') or jsonb_typeof(x->'set_values') is distinct from 'array' or jsonb_array_length(x->'set_values')<1 then return false; end if;
 for s in select * from jsonb_array_elements(x->'set_values') loop
 n=n+1;
 if jsonb_typeof(s) is distinct from 'object' or coalesce((s->>'weight')::numeric,0) not between 0 and 2000 or coalesce((s->>'reps')::int,0) not between 0 and 1000 or coalesce((s->>'durationSeconds')::int,0) not between 0 and 604800 or coalesce((s->>'distanceKm')::numeric,0) not between 0 and 10000 then return false; end if;
 if x->>'record_type' in ('weightReps','bodyweightReps','assistedReps') and coalesce((s->>'reps')::int,0)<1 then return false; end if;
 end loop;
 end loop;
 return n<=100;
 exception when others then return false;
end $$;
create or replace function public.trainer_preview_invite(p_token uuid) returns text language sql stable security definer set search_path='' as $$
 select t.name from public.tenant_invites i join public.tenants t on t.id=i.tenant_id
 where i.token=p_token and i.expires_at>now() and i.used_by is null and auth.uid() is not null and i.created_by<>auth.uid()
$$;
create or replace function public.trainer_accept_invite(p_token uuid,p_name text,p_recording boolean default false,p_heatmap boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare i public.tenant_invites; t uuid; c uuid; email text; s public.tenant_subscriptions;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Verified account required'; end if;
 select tenant_id into t from public.tenant_invites where token=p_token;
 perform 1 from public.tenants where id=t for update;
 select * into i from public.tenant_invites where token=p_token for update;
 if i.id is null or i.used_by is not null or i.expires_at<=now() or i.created_by=auth.uid() then raise exception 'Invalid invite'; end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=t and user_id=i.created_by and status='active' and case when i.kind='staff' then is_admin else is_trainer end) then raise exception 'Inviter no longer authorized'; end if;
 if i.kind='staff' then
 select lower(u.email) into email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if email is null or email<>i.invited_email then raise exception 'Verified invited email required'; end if;
 select * into s from public.tenant_subscriptions where tenant_id=t;
 if s.status='trialing' and i.is_trainer and (select count(*) from public.tenant_memberships where tenant_id=t and status='active' and is_trainer and user_id<>auth.uid())>=5 then raise exception 'Trial allows five trainer IDs'; end if;
 -- Invitations cannot silently downgrade a current member/owner.
 insert into public.tenant_memberships values(t,auth.uid(),i.is_admin,i.is_trainer,'active') on conflict(tenant_id,user_id) do update set is_admin=case when public.tenant_memberships.status='active' then public.tenant_memberships.is_admin or excluded.is_admin else excluded.is_admin end,is_trainer=case when public.tenant_memberships.status='active' then public.tenant_memberships.is_trainer or excluded.is_trainer else excluded.is_trainer end,status='active';
 c=t;
 else
 if i.client_id is not null then
 if not exists(select 1 from public.tenant_assignments where tenant_id=t and client_id=i.client_id and user_id=i.created_by) then raise exception 'Inviter is not assigned'; end if;
 update public.tenant_clients set linked_user_id=auth.uid(),client_name=p_name,status='active',share_workouts=true,allow_recording=p_recording,share_heatmap=p_heatmap,share_body_weight=false,consent_at=now()
 where tenant_id=t and id=i.client_id and (linked_user_id is null or linked_user_id=auth.uid()) returning id into c;
 if c is null then raise exception 'Client already linked'; end if;
 else
 insert into public.tenant_clients(tenant_id,linked_user_id,client_name,share_workouts,allow_recording,share_heatmap,consent_at)
 values(t,auth.uid(),p_name,true,p_recording,p_heatmap,now())
 on conflict(tenant_id,linked_user_id) do update set client_name=excluded.client_name,status='active',share_workouts=true,allow_recording=p_recording,share_heatmap=p_heatmap,consent_at=now() returning id into c;
 insert into public.tenant_assignments values(t,c,i.created_by) on conflict do nothing;
 end if;
 update public.workouts set user_id=auth.uid() where tenant_id=t and tenant_client_id=c and user_id is null;
 end if;
 update public.tenant_invites set used_by=auth.uid() where id=i.id;
 return c;
end $$;
create function public.tenant_my_links() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('client_id',c.linked_user_id,'trainer_profiles',jsonb_build_object('display_name',t.name))), '[]'::jsonb)
 from public.tenant_clients c join public.tenants t on t.id=c.tenant_id where c.linked_user_id=auth.uid() and c.status='active'
$$;
create or replace function public.trainer_revoke_link(p_link uuid) returns void language plpgsql security definer set search_path='' as $$
declare t uuid;
begin
 select tenant_id into t from public.tenant_clients where id=p_link;
 perform 1 from public.tenants where id=t for update;
 update public.tenant_clients set status='revoked',share_workouts=false,allow_recording=false,share_heatmap=false,share_body_weight=false where id=p_link and (linked_user_id=auth.uid() or public.tenant_can_coach(tenant_id,id));
 if not found then raise exception 'Link not found'; end if;
 update public.trainer_client_links set status='revoked',share_workouts=false,allow_recording=false,share_heatmap=false,share_body_weight=false where id=p_link;
end $$;
create function public.tenant_workouts(p_tenant uuid,p_client uuid,p_offset int default 0,p_heatmap boolean default false) returns table(id uuid,performed_at timestamptz,duration_seconds integer,gym_name text,sets jsonb,recorded_by uuid,record_source text,canceled_at timestamptz) language plpgsql stable security definer set search_path='' as $$
declare c public.tenant_clients;
begin
 if not public.tenant_can_coach(p_tenant,p_client) then raise exception 'Assigned trainer required'; end if;
 select tc.* into c from public.tenant_clients tc where tc.tenant_id=p_tenant and tc.id=p_client;
 if c.linked_user_id is not null and (not c.share_workouts or (p_heatmap and not c.share_heatmap)) then raise exception 'Sharing not authorized'; end if;
 return query select w.id,w.performed_at,w.duration_seconds,w.gym_name,w.sets,w.recorded_by,w.record_source,w.canceled_at from public.workouts w
 where (w.tenant_id=p_tenant and w.tenant_client_id=p_client) or (c.linked_user_id is not null and w.user_id=c.linked_user_id and w.tenant_id is null)
 order by w.performed_at desc,w.id limit 100 offset greatest(p_offset,0);
end $$;
create function public.tenant_record(p_tenant uuid,p_client uuid,p_request uuid,p_date timestamptz,p_sets jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.tenant_clients; r uuid; s jsonb; items jsonb='[]';
begin
 perform 1 from public.tenants where id=p_tenant for update;
 if not public.tenant_can_coach(p_tenant,p_client) then raise exception 'Assigned trainer required'; end if;
 select tc.* into c from public.tenant_clients tc where tc.tenant_id=p_tenant and tc.id=p_client;
 if c.linked_user_id is not null and not c.allow_recording then raise exception 'Recording not authorized'; end if;
 if p_request is null or p_date is null or p_date>now()+interval '1 day' or jsonb_typeof(p_sets) is distinct from 'array' or jsonb_array_length(p_sets) not between 1 and 100 then raise exception 'Invalid workout'; end if;
 for s in select * from jsonb_array_elements(p_sets) loop
 if (s->>'completed')::boolean is distinct from true then raise exception 'Incomplete set'; end if;
 items=items||jsonb_build_array(jsonb_build_object('exercise_id',s->>'exerciseId','exercise_name',s->>'exerciseName','record_type',s->>'recordType','set_values',jsonb_build_array(s)));
 end loop;
 if not public.tenant_valid_items(items) then raise exception 'Invalid set values'; end if;
 insert into public.workouts(user_id,client_id,tenant_id,tenant_client_id,performed_at,sets,recorded_by,record_source)
 values(c.linked_user_id,'tenant:'||p_client::text||':'||p_request::text,p_tenant,p_client,p_date,p_sets,auth.uid(),'trainer')
 on conflict(tenant_id,client_id) do nothing returning id into r;
 if r is null then select id into r from public.workouts where tenant_id=p_tenant and client_id='tenant:'||p_client::text||':'||p_request::text; end if;
 return r;
end $$;
create function public.tenant_cancel_record(p_tenant uuid,p_client uuid,p_record uuid,p_cancel boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.tenants where id=p_tenant for update;
 if not public.tenant_can_coach(p_tenant,p_client) then raise exception 'Assigned trainer required'; end if;
 if exists(select 1 from public.tenant_clients where id=p_client and linked_user_id is not null and not allow_recording) then raise exception 'Recording not authorized'; end if;
 update public.workouts set canceled_at=case when p_cancel then now() end,canceled_by=case when p_cancel then auth.uid() end
 where id=p_record and tenant_id=p_tenant and tenant_client_id=p_client and record_source='trainer';
 if not found then raise exception 'Tenant record not found'; end if;
end $$;
-- Preserve owner scope and attribution while preventing clients from moving/uncanceling tenant records or hard deleting them.
create or replace function public.trainer_guard_attribution() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('anon','authenticated') then
 if tg_op='DELETE' then
 if old.tenant_id is not null then raise exception 'Tenant records must be canceled'; end if;
 return old;
 elsif tg_op='INSERT' then
 new.recorded_by=auth.uid(); new.record_source='self'; new.tenant_id=null; new.tenant_client_id=null; new.canceled_at=null; new.canceled_by=null;
 else
 new.recorded_by=old.recorded_by; new.record_source=old.record_source;
 new.tenant_id=old.tenant_id; new.tenant_client_id=old.tenant_client_id; new.canceled_at=old.canceled_at; new.canceled_by=old.canceled_by;
 end if;
 end if;
 return coalesce(new,old);
end $$;
create trigger tenant_no_hard_delete before delete on public.workouts for each row execute function public.trainer_guard_attribution();
-- Retired trainer-only writes cannot bypass tenant membership. Old rows are preserved as migration evidence.
revoke insert,update,delete on public.trainer_notes,public.trainer_menus from authenticated;
revoke execute on function public.trainer_create_invite(),public.trainer_client_workouts(uuid,integer),public.trainer_record_workout(uuid,uuid,timestamptz,jsonb) from authenticated;
-- Revoke legacy reads that could leak retained notes after membership removal.
revoke select on public.trainer_notes,public.trainer_menus from authenticated;
create or replace function public.trainer_share_workout(p_date timestamptz,p_duration integer,p_gym text,p_sets jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.tenant_clients where linked_user_id=auth.uid() and status='active' and share_workouts for share;
 if not found then raise exception 'No active sharing link'; end if;
 if p_date is null or jsonb_typeof(p_sets) is distinct from 'array' or jsonb_array_length(p_sets) not between 1 and 1000 then raise exception 'Invalid workout'; end if;
 if exists(select 1 from public.workouts where user_id=auth.uid() and performed_at=p_date and record_source='trainer') then return; end if;
 update public.workouts set sets=p_sets,duration_seconds=p_duration,gym_name=p_gym,updated_at=now() where user_id=auth.uid() and performed_at=p_date and record_source='self';
 if not found then insert into public.workouts(user_id,client_id,performed_at,duration_seconds,gym_name,sets,recorded_by) values(auth.uid(),p_date::text,p_date,p_duration,p_gym,p_sets,auth.uid()); end if;
end $$;
-- Billing updates are service-role only. Wire ONLY behind a verified Stripe webhook.
create table public.tenant_billing_events(event_id text primary key,tenant_id uuid not null references public.tenants(id),created_at timestamptz not null default now());
alter table public.tenant_billing_events enable row level security;
revoke all on public.tenant_billing_events from public,anon,authenticated;
create function public.tenant_apply_billing(p_tenant uuid,p_event text,p_status text,p_customer text,p_subscription text,p_card_ready boolean) returns void language plpgsql security definer set search_path='' as $$
declare s public.tenant_subscriptions;
begin
 perform 1 from public.tenants where id=p_tenant for update;
 if exists(select 1 from public.tenant_billing_events where event_id=p_event) then return; end if;
 select * into s from public.tenant_subscriptions where tenant_id=p_tenant for update;
 if not found then raise exception 'Subscription not found'; end if;
 if p_status='trialing' and s.status<>'trialing' then
 if not p_card_ready or s.trial_used_at is not null or (select count(*) from public.tenant_memberships where tenant_id=p_tenant and status='active' and is_trainer)>5 then raise exception 'Trial not eligible'; end if;
 s.trial_used_at=now(); s.trial_ends_at=now()+interval '14 days';
 end if;
 if p_status='trialing' and s.trial_ends_at<=now() then raise exception 'Trial expired'; end if;
 update public.tenant_subscriptions set status=p_status,stripe_customer_id=p_customer,stripe_subscription_id=p_subscription,payment_method_ready=p_card_ready,trial_used_at=s.trial_used_at,trial_ends_at=s.trial_ends_at,updated_at=now() where tenant_id=p_tenant;
 insert into public.tenant_billing_events(event_id,tenant_id) values(p_event,p_tenant);
end $$;
create function public.tenant_members(p_tenant uuid) returns table(tenant_id uuid,user_id uuid,is_admin boolean,is_trainer boolean,status text,display_name text,email text) language plpgsql stable security definer set search_path='' as $$
begin
 if not public.tenant_has_role(p_tenant) then raise exception 'Active membership required'; end if;
 return query select m.tenant_id,m.user_id,m.is_admin,m.is_trainer,m.status,coalesce(p.display_name,u.email,'Member'),case when public.tenant_has_role(p_tenant,'admin') then u.email end
 from public.tenant_memberships m join auth.users u on u.id=m.user_id left join public.trainer_profiles p on p.user_id=m.user_id
 where m.tenant_id=p_tenant and (m.status='active' or public.tenant_has_role(p_tenant,'admin'));
end $$;
-- Explicitly close PostgreSQL's default PUBLIC function EXECUTE grant.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'tenant_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname not in ('tenant_audit_change','tenant_apply_billing') then execute format('grant execute on function %s to authenticated',f.signature); end if;
 end loop;
end $$;
grant execute on function public.tenant_apply_billing(uuid,text,text,text,text,boolean) to service_role;
commit;
