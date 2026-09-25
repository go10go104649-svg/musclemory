-- Run after schema.sql + trainer migration against a disposable database only.
-- No pgTAP dependency. Every assertion raises on failure; all fixture data rolls back.
begin;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$ begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
create function pg_temp.denied(statement text) returns boolean language plpgsql as $$ begin execute statement; return false; exception when others then return true; end $$;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
insert into public.trainer_profiles(user_id,display_name) values(auth.uid(),'Trainer One');
select public.trainer_create_invite() as invite \gset
select pg_temp.assert_true(pg_temp.denied(format('select public.trainer_accept_invite(%L,%L)',:'invite','self')),'self-link denied');
select pg_temp.assert_true(pg_temp.denied($q$select * from public.trainer_client_workouts('00000000-0000-0000-0000-000000000002')$q$),'unlinked history denied');
select pg_temp.assert_true(pg_temp.denied($q$insert into public.trainer_client_links(trainer_id,client_id,client_name) values(auth.uid(),'00000000-0000-0000-0000-000000000002','Victim')$q$),'cannot forge link');
select pg_temp.assert_true(pg_temp.denied($q$insert into public.trainer_profiles(user_id,display_name) values('00000000-0000-0000-0000-000000000002','forged')$q$),'cannot forge trainer role');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true(public.trainer_preview_invite(:'invite')='Trainer One','preview identifies trainer');
select public.trainer_accept_invite(:'invite','Client Two',false,false) as link \gset
select pg_temp.assert_true((select not share_body_weight and not allow_recording and not share_heatmap from public.trainer_client_links where id=:'link'),'sensitive permissions default off');
select pg_temp.assert_true(pg_temp.denied(format('select public.trainer_accept_invite(%L,%L)',:'invite','again')),'invite single use');
insert into public.workouts(user_id,client_id,performed_at,sets,recorded_by,record_source) values(auth.uid(),'existing','2026-09-24T00:00:00Z','[]','00000000-0000-0000-0000-000000000001','trainer');
select pg_temp.assert_true((select recorded_by=auth.uid() and record_source='self' from public.workouts where client_id='existing'),'owner insert cannot forge attribution');
select pg_temp.assert_true((select count(*)=0 from public.trainer_notes),'client cannot read trainer notes');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from public.workouts),'owner-only direct workout RLS preserved');
select pg_temp.assert_true((select count(*)=1 from public.trainer_client_workouts('00000000-0000-0000-0000-000000000002')),'linked read permitted');
select pg_temp.assert_true(pg_temp.denied($q$select public.trainer_record_workout('00000000-0000-0000-0000-000000000002',gen_random_uuid(),now(),'[{"exerciseId":"bench","exerciseName":"Bench","recordType":"weightReps","weight":20,"reps":10,"completed":true}]')$q$),'recording separately gated');
insert into public.trainer_notes(client_id,body) values('00000000-0000-0000-0000-000000000002','Private note');
insert into public.trainer_menus(client_id,name,items) values('00000000-0000-0000-0000-000000000002','Plan','[{"exercise_id":"bench","exercise_name":"Bench","sets":3,"target_weight":20,"target_reps":10}]');
select pg_temp.assert_true(pg_temp.denied($q$update public.trainer_client_links set allow_recording=true$q$),'trainer cannot grant permission');
select pg_temp.assert_true(pg_temp.denied($q$insert into public.trainer_menus(client_id,name,items) values('00000000-0000-0000-0000-000000000002','Bad','[{"exercise_id":"bench","exercise_name":"Bench","sets":-1,"target_weight":20,"target_reps":10}]')$q$),'invalid menu rejected');
select public.trainer_create_invite() as invite2 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.trainer_notes),'private notes invisible to client');
select pg_temp.assert_true((select count(*)=0 from public.trainer_menus),'private draft menus invisible to client');
select public.trainer_accept_invite(:'invite2','Client Two',true,true);
select public.trainer_share_workout('2026-09-23T00:00:00Z',60,null,'[{"exerciseName":"Bench","weight":20,"reps":10}]');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select public.trainer_record_workout('00000000-0000-0000-0000-000000000002','11111111-1111-4111-8111-111111111111',now(),'[{"exerciseId":"bench","exerciseName":"Bench","recordType":"weightReps","weight":20,"reps":10,"completed":true}]');
select public.trainer_record_workout('00000000-0000-0000-0000-000000000002','11111111-1111-4111-8111-111111111111',now(),'[{"exerciseId":"bench","exerciseName":"Bench","recordType":"weightReps","weight":20,"reps":10,"completed":true}]');
select pg_temp.assert_true((select count(*)=3 from public.trainer_client_workouts('00000000-0000-0000-0000-000000000002')),'idempotent session retries');
select pg_temp.assert_true(pg_temp.denied($q$select public.trainer_record_workout('00000000-0000-0000-0000-000000000002',gen_random_uuid(),now(),'[{"exerciseId":"bench","exerciseName":"Bench","recordType":"weightReps","weight":-20,"reps":10,"completed":true}]')$q$),'negative weight denied');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.trainer_profiles),'cannot enumerate trainers');
select pg_temp.assert_true((select count(*)=0 from public.trainer_client_links),'cannot enumerate clients');
select pg_temp.assert_true((select count(*)=0 from public.trainer_notes),'cannot enumerate notes');
select pg_temp.assert_true((select count(*)=0 from public.trainer_menus),'cannot enumerate menus');
select pg_temp.assert_true(pg_temp.denied($q$select * from public.trainer_client_workouts('00000000-0000-0000-0000-000000000002')$q$),'substituting client ID denied');
select pg_temp.assert_true(pg_temp.denied(format('select public.trainer_revoke_link(%L)',:'link')),'unrelated revoke denied');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=1 from public.workouts where record_source='trainer' and recorded_by='00000000-0000-0000-0000-000000000001'),'session saved in client original history');
update public.workouts set recorded_by=auth.uid(),record_source='self' where record_source='trainer';
select pg_temp.assert_true((select count(*)=1 from public.workouts where record_source='trainer'),'attribution immutable on owner update');
select public.trainer_revoke_link(:'link');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true(pg_temp.denied($q$select * from public.trainer_client_workouts('00000000-0000-0000-0000-000000000002')$q$),'revoked read denied');
select pg_temp.assert_true(pg_temp.denied($q$select public.trainer_record_workout('00000000-0000-0000-0000-000000000002',gen_random_uuid(),now(),'[]')$q$),'revoked write denied');
select pg_temp.assert_true(pg_temp.denied($q$insert into public.trainer_notes(client_id,body) values('00000000-0000-0000-0000-000000000002','blocked')$q$),'no new notes after revoke');
select pg_temp.assert_true((select count(*)=1 from public.trainer_notes),'own notes retained');
select public.trainer_create_invite() as old_invite \gset
select public.trainer_create_invite() as new_invite \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true(public.trainer_preview_invite(:'old_invite') is null,'rotated invite invalid');
reset role;
update public.trainer_invites set expires_at=now()-interval '1 second' where token=:'new_invite';
set local role authenticated;
select pg_temp.assert_true(public.trainer_preview_invite(:'new_invite') is null,'expired preview invalid');
select pg_temp.assert_true(pg_temp.denied(format('select public.trainer_accept_invite(%L,%L)',:'new_invite','expired')),'expired acceptance denied');
set local role anon;
select pg_temp.assert_true(pg_temp.denied($q$select public.trainer_create_invite()$q$),'anonymous RPC denied');
select pg_temp.assert_true(pg_temp.denied($q$select * from public.trainer_client_links$q$),'anonymous table access denied');
rollback;
