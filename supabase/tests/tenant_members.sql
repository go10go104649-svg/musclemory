-- Disposable DB only, after 202609260001. Match Supabase's real email type.
begin;
alter table auth.users alter column email type varchar(255);
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end$$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$begin execute q;return false;exception when others then return true;end$$;
insert into auth.users(id,email,email_confirmed_at)
select ('40000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'member'||n||'@test.invalid',now() from generate_series(1,4)n;
insert into public.trainer_profiles(user_id,display_name) values ('40000000-0000-0000-0000-000000000001','Coach');
set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
select public.tenant_create('くま') as tenant \gset
reset role;
insert into public.tenant_memberships values
(:'tenant','40000000-0000-0000-0000-000000000002',false,true,'active'),
(:'tenant','40000000-0000-0000-0000-000000000003',false,true,'removed');
set local role authenticated;
select pg_temp.ok((select count(*)=3 and count(email)=3 from public.tenant_members(:'tenant')),'admin loads active/inactive members and email with varchar source');
select pg_temp.ok((select display_name='Coach' from public.tenant_members(:'tenant') where user_id=auth.uid()),'profile display name retained');
select pg_temp.ok((select display_name='member2@test.invalid' from public.tenant_members(:'tenant') where user_id='40000000-0000-0000-0000-000000000002'),'missing profile uses email fallback');
select pg_temp.ok((select count(*)=1 from public.trainer_profiles where user_id=auth.uid()),'reload profile readable');
select pg_temp.ok((select count(*)=0 from public.tenant_assignments where tenant_id=:'tenant'),'empty assignments readable');
select pg_temp.ok((select count(*)=0 from public.tenant_clients where tenant_id=:'tenant'),'empty clients readable');
select pg_temp.ok((select count(*)=0 from public.tenant_menus where tenant_id=:'tenant'),'empty menus readable');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=2 and count(email)=0 from public.tenant_members(:'tenant')),'non-admin loads active members with email column hidden');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000003',true);
select pg_temp.ok(pg_temp.denied(format('select * from public.tenant_members(%L)',:'tenant')),'inactive member denied');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000004',true);
select pg_temp.ok(pg_temp.denied(format('select * from public.tenant_members(%L)',:'tenant')),'unrelated user denied');
set local role anon;
select pg_temp.ok(pg_temp.denied(format('select * from public.tenant_members(%L)',:'tenant')),'anonymous execution remains denied');
rollback;
