-- Disposable DB after 202609250003. Everything is rolled back.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end$$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$begin execute q;return false;exception when others then return true;end$$;
insert into auth.users(id,email,email_confirmed_at)
select ('30000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'delivery'||n||'@test.invalid',now() from generate_series(1,5)n;
set local role authenticated;
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000001',true);
select public.tenant_create('Delivery') as tenant \gset
select public.tenant_create('Other tenant') as other_tenant \gset
select public.tenant_mutate(:'tenant','client','{"name":"A"}')->>'id' as a \gset
select public.tenant_mutate(:'tenant','client','{"name":"B"}')->>'id' as b \gset
select public.tenant_mutate(:'other_tenant','client','{"name":"Other"}')->>'id' as other_client \gset
select '[{"exercise_id":"bench_press","exercise_name":"Bench","body_part":"胸","equipment":"barbell","record_type":"weightReps","set_values":[{"weight":20,"reps":10},{"weight":25,"reps":8}]},{"exercise_id":"running","exercise_name":"Run","record_type":"cardio","set_values":[{"durationSeconds":600,"distanceKm":1.5,"speedKmh":9,"inclinePercent":2,"paceSecondsPerKm":400,"distanceUnit":"km"}]}]'::jsonb as items \gset
select public.tenant_mutate(:'tenant','menu',jsonb_build_object('client_id',:'a','name','A menu','items',:'items'::jsonb))->>'id' as menu_a \gset
select public.tenant_mutate(:'tenant','menu',jsonb_build_object('client_id',:'b','name','B menu','items',:'items'::jsonb))->>'id' as menu_b \gset
select public.tenant_save_comment(:'tenant',:'a','A comment',p_menu=>:'menu_a',p_date=>'2026-09-25') as comment_a \gset
select public.tenant_save_comment(:'tenant',:'b','B comment') as comment_b \gset
select public.tenant_mutate(:'tenant','comment',jsonb_build_object('client_id',:'a','body','Private old note'))->>'id' as private_note \gset
select pg_temp.ok((select not shared_with_client and edited_by=created_by from public.tenant_comments where id=:'private_note'),'old RPC remains private and compatible');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L,p_menu=>%L)',:'tenant',:'a','cross',:'menu_b')),'cross-client menu attachment denied');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L)',:'other_tenant',:'a','cross')),'cross-tenant attachment denied');
select public.tenant_mutate(:'tenant','client_invite',jsonb_build_object('client_id',:'a'))->>'id' as invite_a \gset
select public.tenant_mutate(:'tenant','client_invite',jsonb_build_object('client_id',:'b'))->>'id' as invite_b \gset
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.tenant_menus),'unlinked account cannot see offline menus');
select public.trainer_accept_invite(:'invite_a','Client A',false,false);
select pg_temp.ok((select count(*)=1 from public.tenant_menus),'A sees exactly its menu');
select pg_temp.ok((select count(*)=2 from public.tenant_menu_exercises),'A sees only own exercises');
select pg_temp.ok((select count(*)=3 from public.tenant_menu_sets),'A sees only own sets');
select pg_temp.ok((select count(*)=0 from public.tenant_menus where id=:'menu_b'),'A cannot fetch B by known ID');
select pg_temp.ok((select count(*)=1 from public.tenant_comments),'A sees shared comment, not private coaching note');
select pg_temp.ok((select menu_id=:'menu_a' and workout_date='2026-09-25' and created_by='30000000-0000-0000-0000-000000000001' and updated_at is not null from public.tenant_comments where id=:'comment_a'),'comment retains identity and related menu/date');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L,p_id=>%L,p_version=>1)',:'tenant',:'a','hack',:'comment_a')),'client cannot edit own comment');
select pg_temp.ok(pg_temp.denied(format('update public.tenant_menus set name=%L where id=%L','hack',:'menu_a')),'client cannot directly edit menu');
select pg_temp.ok(pg_temp.denied(format('delete from public.tenant_comments where id=%L',:'comment_a')),'client cannot directly delete comment');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000003',true);
select public.trainer_accept_invite(:'invite_b','Client B',false,false);
select pg_temp.ok((select count(*)=1 and min(name)='B menu' from public.tenant_menus),'B sees B menu only');
select pg_temp.ok((select count(*)=0 from public.tenant_comments where id=:'comment_a'),'B cannot fetch A comment by ID');
select pg_temp.ok((select count(*)=1 and min(body)='B comment' from public.tenant_comments),'B sees B comment only');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000001',true);
select public.tenant_mutate(:'tenant','menu',jsonb_build_object('id',:'menu_a','client_id',:'a','version',1,'name','A updated','schedule','repeat','items',replace(:'items','"weight": 20','"weight": 30')::jsonb));
select public.tenant_save_comment(:'tenant',:'a','A edited',p_id=>:'comment_a',p_version=>1);
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L,p_id=>%L,p_version=>1)',:'tenant',:'a','stale',:'comment_a')),'stale comment version rejected');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L,p_id=>%L,p_version=>2)',:'tenant',:'b','wrong client',:'comment_a')),'comment client cannot be changed');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select name='A updated' and version=2 and schedule='repeat' from public.tenant_menus where id=:'menu_a'),'A reads latest menu without copied rows');
select pg_temp.ok((select (s.values->>'weight')::int=30 from public.tenant_menu_sets s join public.tenant_menu_exercises e on e.id=s.exercise_id where e.menu_id=:'menu_a' and e.position=1 and s.position=1),'A reads updated per-set target');
select pg_temp.ok((select body='A edited' and version=2 and updated_at>=created_at from public.tenant_comments where id=:'comment_a'),'A reads edited comment under same ID');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000001',true);
select public.tenant_save_comment(:'tenant',:'a','Private now',p_id=>:'comment_a',p_version=>2,p_shared=>false);
select public.tenant_save_comment(:'tenant',:'a','Explicitly published old note',p_id=>:'private_note',p_version=>1,p_shared=>true);
select public.tenant_mutate(:'tenant','menu_status',jsonb_build_object('id',:'menu_a','client_id',:'a','version',2,'status','canceled'));
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.tenant_comments where id=:'comment_a'),'unsharing removes comment from A');
select pg_temp.ok((select count(*)=1 from public.tenant_comments where id=:'private_note'),'explicit publication exposes old note');
select pg_temp.ok((select count(*)=0 from public.tenant_menus),'canceled menu hidden');
select pg_temp.ok((select count(*)=0 from public.tenant_menu_exercises),'canceled menu children hidden');
select pg_temp.ok((select count(*)=0 from public.tenant_menu_sets),'canceled menu sets hidden');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000001',true);
select public.tenant_save_comment(:'tenant',:'a','',p_id=>:'private_note',p_version=>2,p_delete=>true);
select public.tenant_mutate(:'tenant','menu_status',jsonb_build_object('id',:'menu_a','client_id',:'a','version',3,'status','planned'));
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.tenant_comments),'deleted comment disappears');
select pg_temp.ok((select count(*)=1 from public.tenant_menus),'restored menu visible');
select public.trainer_revoke_link(:'a');
select pg_temp.ok((select count(*)=0 from public.tenant_menus),'revocation removes menus');
select pg_temp.ok((select count(*)=0 from public.tenant_menu_sets),'revocation removes nested sets');
select set_config('request.jwt.claim.sub','30000000-0000-0000-0000-000000000004',true);
select pg_temp.ok((select count(*)=0 from public.tenant_comments),'unrelated user sees no comments');
select pg_temp.ok((select count(*)=0 from public.tenant_menus),'unrelated user sees no menus');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L)',:'tenant',:'b','intruder')),'unassigned user cannot write comments');
set local role anon;
select pg_temp.ok(pg_temp.denied('select * from public.tenant_menus'),'anonymous cannot read menus');
select pg_temp.ok(pg_temp.denied(format('select public.tenant_save_comment(%L,%L,%L)',:'tenant',:'b','anon')),'anonymous cannot call comment RPC');
reset role;
select pg_temp.ok((select count(*)=4 from pg_class where relname in ('tenant_menus','tenant_menu_exercises','tenant_menu_sets','tenant_comments') and relrowsecurity),'all shared tables still have RLS');
select pg_temp.ok((select count(*)=2 from public.tenant_menus where tenant_id=:'tenant'),'no menu data duplication');
select pg_temp.ok((select count(*)>0 from public.tenant_audit where entity_id=:'private_note' and action='tenant_comments.delete'),'comment deletion audited');
rollback;
