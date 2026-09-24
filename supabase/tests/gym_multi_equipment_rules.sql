begin;

insert into public.gym_chains (id, name)
values ('qa-multi-chain', 'QA multi chain')
on conflict (id) do update set name = excluded.name;

insert into public.gym_stores (
  id, chain_id, source_id, name, equipment_status
) values (
  'qa-multi-store', 'qa-multi-chain', 'qa-multi-store', 'QA multi store', 'published'
)
on conflict (id) do update set equipment_status = excluded.equipment_status;

insert into public.equipment (
  id, name, normalized_name, category, load_type, needs_review
) values
  ('qa-multi-rack', 'QA rack', 'QA rack', 'フリーウェイト', 'not_specified', false),
  ('qa-multi-bench', 'QA bench', 'QA bench', 'フリーウェイト', 'not_specified', false)
on conflict (id) do update set name = excluded.name;

insert into public.gym_store_equipment (
  store_id, equipment_id, available, raw_name
) values (
  'qa-multi-store', 'qa-multi-rack', true, 'QA rack'
)
on conflict (store_id, equipment_id)
do update set available = excluded.available;

insert into public.equipment_exercise_mapping (
  equipment_id, exercise_id, rationale
) values (
  'qa-multi-rack', 'qa_direct_exercise', 'QA direct'
)
on conflict (equipment_id, exercise_id)
do update set rationale = excluded.rationale;

insert into public.exercise_equipment_rules (id, exercise_id, rationale)
values ('qa-rack-bench-rule', 'qa_composite_exercise', 'QA composite')
on conflict (id)
do update set exercise_id = excluded.exercise_id, rationale = excluded.rationale;

insert into public.exercise_equipment_rule_items (rule_id, equipment_id)
values
  ('qa-rack-bench-rule', 'qa-multi-rack'),
  ('qa-rack-bench-rule', 'qa-multi-bench')
on conflict (rule_id, equipment_id) do nothing;

do $$
begin
  if not exists (
    select 1
    from public.gym_store_exercise_ids('qa-multi-store')
    where exercise_id = 'qa_direct_exercise'
  ) then
    raise exception 'direct mapping was not returned';
  end if;

  if exists (
    select 1
    from public.gym_store_exercise_ids('qa-multi-store')
    where exercise_id = 'qa_composite_exercise'
  ) then
    raise exception 'composite mapping returned before all requirements existed';
  end if;
end;
$$;

insert into public.gym_store_equipment (
  store_id, equipment_id, available, raw_name
) values (
  'qa-multi-store', 'qa-multi-bench', true, 'QA bench'
)
on conflict (store_id, equipment_id)
do update set available = excluded.available;

do $$
begin
  if not exists (
    select 1
    from public.gym_store_exercise_ids('qa-multi-store')
    where exercise_id = 'qa_composite_exercise'
  ) then
    raise exception 'composite mapping was not returned when all requirements existed';
  end if;
end;
$$;

rollback;
