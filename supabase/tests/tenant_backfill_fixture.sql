-- BEFORE tenant migration, on a disposable database with trainer foundation only.
insert into auth.users(id,email,email_confirmed_at) values
('30000000-0000-0000-0000-000000000001','legacy1@test.invalid',now()),
('30000000-0000-0000-0000-000000000002','legacy2@test.invalid',now()),
('30000000-0000-0000-0000-000000000003','client@test.invalid',now());
insert into public.trainer_profiles(user_id,display_name) values('30000000-0000-0000-0000-000000000001','Legacy One'),('30000000-0000-0000-0000-000000000002','Legacy Two');
insert into public.trainer_client_links(id,trainer_id,client_id,client_name,allow_recording,share_heatmap)
 values('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','Same Client',true,true),
 ('40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000003','Same Client',false,false);
insert into public.trainer_menus(id,trainer_id,client_id,name,items) values('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','Legacy menu','[{"exercise_id":"bench_press","exercise_name":"Bench","body_part":"胸","equipment":"barbell","record_type":"weightReps","sets":3,"target_weight":20,"target_reps":10}]');
insert into public.trainer_notes(id,trainer_id,client_id,body)values('60000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','Legacy cue');
insert into public.workouts(id,user_id,client_id,performed_at,sets,recorded_by,record_source) values('70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','legacy-session',now(),'[]','30000000-0000-0000-0000-000000000001','trainer');
insert into public.trainer_invites(id,token,trainer_id)values('80000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');
