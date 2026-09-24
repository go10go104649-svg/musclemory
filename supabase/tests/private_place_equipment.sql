begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000010'),('00000000-0000-4000-8000-000000000011');
insert into public.gym_chains(id,name) values ('qa-private','QA');
insert into public.gym_stores(id,chain_id,source_id,name) values ('qa-private-store','qa-private','one','QA');
insert into public.equipment(id,name,normalized_name,category) values ('qa-private-rack','ラック','ラック','フリーウェイト'),('qa-private-bench','ベンチ','ベンチ','フリーウェイト');
insert into public.equipment_exercise_mapping(equipment_id,exercise_id,rationale) values ('qa-private-rack','barbell_squat','QA');
insert into public.exercise_equipment_rules(id,exercise_id) values ('qa-private-rule','bench_press');
insert into public.exercise_equipment_rule_items values ('qa-private-rule','qa-private-rack'),('qa-private-rule','qa-private-bench');
insert into public.gym_store_equipment(store_id,equipment_id,raw_name) values ('qa-private-store','qa-private-rack','ラック'),('qa-private-store','qa-private-bench','ベンチ');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000010';
set local role authenticated;
insert into public.user_custom_place_equipment(id,custom_place_id,equipment_id,name) values ('r','qa-place','qa-private-rack','ラック'),('b','qa-place','qa-private-bench','ベンチ');
insert into public.user_custom_place_equipment(id,custom_place_id,name) values ('free','qa-place','名称だけのベンチ');
do $$ begin
 if exists(select 1 from public.equipment_exercise_evidence(array['qa-private-rack']) where exercise_id='bench_press') then raise exception 'Missing bench satisfied rule'; end if;
 if not exists(select 1 from public.equipment_exercise_evidence(array['qa-private-rack','qa-private-bench']) where exercise_id='bench_press') then raise exception 'Complete rule missing'; end if;
 if exists((select * from public.gym_store_exercise_ids('qa-private-store')) except (select distinct exercise_id from public.equipment_exercise_evidence(array['qa-private-rack','qa-private-bench']))) then raise exception 'Shared evaluator mismatch';end if;
 if (select count(*) from public.gym_store_equipment where store_id='qa-private-store')<>2 then raise exception 'Private data leaked to shared inventory';end if;
end $$;
update public.user_custom_place_equipment set quantity=2 where id='r';
insert into public.gym_exercise_reports(store_id,exercise_id,report_kind) values ('qa-private-store','bench_press','missing_exercise'),('qa-private-store','bench_press','missing_exercise'),('qa-private-store','barbell_squat','incorrect_exercise');
insert into public.gym_exercise_reports(store_id,report_kind,comment) values ('qa-private-store','other','確認してください'),('qa-private-store','other','別の確認事項');
do $$ begin
 if not exists(select 1 from public.gym_exercise_reports where store_id='qa-private-store' and exercise_id='bench_press' and status='pending' and user_id=auth.uid()) then raise exception 'Report payload/defaults failed';end if;
 if (select count(*) from public.gym_exercise_reports where store_id='qa-private-store')<>4 then raise exception 'Report duplication/types failed';end if;
 if not exists(select 1 from public.gym_store_exercise_ids('qa-private-store') where exercise_id='barbell_squat') then raise exception 'Report changed master';end if;
 begin
 insert into public.user_custom_place_equipment(id,user_id,custom_place_id,name) values ('bad','00000000-0000-4000-8000-000000000011','qa-place','不正');
 raise exception 'RLS allowed foreign insert';
 exception when insufficient_privilege then null;end;
 begin
 insert into public.gym_exercise_reports(store_id,report_kind,comment,status) values ('qa-private-store','other','不正','applied');
 raise exception 'Self approval allowed';exception when insufficient_privilege then null;end;
end $$;
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000011';
do $$ begin
 if exists(select 1 from public.user_custom_place_equipment where custom_place_id='qa-place') then raise exception 'Private inventory exposed';end if;
 if exists(select 1 from public.gym_exercise_reports where store_id='qa-private-store') then raise exception 'Reports exposed';end if;
end $$;
update public.user_custom_place_equipment set quantity=9 where custom_place_id='qa-place';
delete from public.user_custom_place_equipment where custom_place_id='qa-place';
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000010';
do $$ begin
 if (select quantity from public.user_custom_place_equipment where id='r' and custom_place_id='qa-place')<>2 then raise exception 'Foreign update/delete succeeded';end if;
end $$;
delete from public.user_custom_place_equipment where custom_place_id='qa-place';
rollback;
select 'private equipment, shared rules, reports and RLS passed' result;
