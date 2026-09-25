-- AFTER migration on the fixture database. No production use.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAILED: %',label;end if;end$$;
select pg_temp.ok((select count(*)=2 from public.tenants),'trainers never inferred into one tenant');
select pg_temp.ok((select count(distinct tenant_id)=2 from public.tenant_clients where linked_user_id='30000000-0000-0000-0000-000000000003'),'same user has independent client entities');
select pg_temp.ok((select id=md5('setkeep.personal.30000000-0000-0000-0000-000000000001')::uuid from public.tenants where legacy_trainer_id='30000000-0000-0000-0000-000000000001'),'deterministic personal tenant');
select pg_temp.ok((select count(*)=1 from public.trainer_menus),'legacy rows retained');
select pg_temp.ok((select count(*)=3 from public.tenant_menu_sets where values->>'weight'='20' and values->>'reps'='10'),'aggregate target expanded to exact sets');
select pg_temp.ok((select body='Legacy cue' from public.tenant_comments where id='60000000-0000-0000-0000-000000000001'),'comment id and contents retained');
select pg_temp.ok((select allow_recording and share_heatmap from public.tenant_clients where id='40000000-0000-0000-0000-000000000001'),'consents retained');
select pg_temp.ok((select not allow_recording and not share_heatmap from public.tenant_clients where id='40000000-0000-0000-0000-000000000002'),'denied consents not broadened');
select pg_temp.ok((select count(*)=1 from public.workouts where id='70000000-0000-0000-0000-000000000001' and tenant_client_id='40000000-0000-0000-0000-000000000001' and user_id='30000000-0000-0000-0000-000000000003'),'workout ownership and ID retained');
set local role authenticated;
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000003',true);
select pg_temp.ok(public.trainer_preview_invite('90000000-0000-0000-0000-000000000001')='Legacy One','old QR token remains valid');
select public.trainer_accept_invite('90000000-0000-0000-0000-000000000001','Same Client',true,true);
select pg_temp.ok(jsonb_array_length(public.tenant_my_links())=2,'legacy invitation does not duplicate client');
rollback;
