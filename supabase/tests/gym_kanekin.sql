begin;

do $$
declare
  listed_count integer;
  relation_count integer;
begin
  if not exists (
    select 1 from public.search_gym_stores_v2('カネキンジム', 0, null) j
    where j->>'id' = 'kanekin-fitness-gym:matsudo'
  ) then
    raise exception 'Kanekin store was not found through its Japanese alias';
  end if;

  select count(*) into listed_count
  from public.equipment
  where source->>'snapshot_id' = 'official-page-2026-09-24';
  select count(*) into relation_count
  from public.gym_store_equipment
  where store_id = 'kanekin-fitness-gym:matsudo';

  if listed_count <> 37 or relation_count <> 37 then
    raise exception 'Expected 37 listed equipment rows, got equipment %, relations %',
      listed_count, relation_count;
  end if;

  if exists (
    select 1 from public.gym_store_equipment
    where store_id = 'kanekin-fitness-gym:matsudo'
      and (quantity is not null or checked_at is not null or source_kind <> 'official')
  ) then
    raise exception 'Unknown quantity/date or official source provenance was lost';
  end if;

  if exists (
    select required.exercise_id
    from (values
      ('incline_fly_machine'),
      ('belt_squat'),
      ('bench_press'),
      ('exercise_bike'),
      ('hip_abduction'),
      ('hip_adduction'),
      ('incline_barbell_press'),
      ('incline_dumbbell_press')
    ) required(exercise_id)
    where not exists (
      select 1
      from public.gym_store_exercise_ids('kanekin-fitness-gym:matsudo') actual
      where actual.exercise_id = required.exercise_id
    )
  ) then
    raise exception 'Direct or multi-equipment exercise evidence is incomplete';
  end if;
end;
$$;

-- Removing a store relation must leave the shared equipment master intact and
-- immediately remove this store's unique exercise evidence.
delete from public.gym_store_equipment
where store_id = 'kanekin-fitness-gym:matsudo'
  and equipment_id = 'kanekin:delta-belt-squat';

do $$
begin
  if not exists (
    select 1 from public.equipment where id = 'kanekin:delta-belt-squat'
  ) then
    raise exception 'Store removal deleted the equipment master';
  end if;
  if exists (
    select 1 from public.gym_store_exercise_ids('kanekin-fitness-gym:matsudo')
    where exercise_id = 'belt_squat'
  ) then
    raise exception 'Removed equipment still contributes store exercise evidence';
  end if;
end;
$$;

-- Incline free-weight movements require one of the explicitly adjustable
-- benches. Removing both must not affect flat-bench or direct machine evidence.
delete from public.gym_store_equipment
where store_id = 'kanekin-fitness-gym:matsudo'
  and equipment_id in (
    'kanekin:bull-adjustable-bench',
    'kanekin:rogue-adjustable-bench'
  );

do $$
begin
  if exists (
    select 1 from public.gym_store_exercise_ids('kanekin-fitness-gym:matsudo')
    where exercise_id in ('incline_barbell_press', 'incline_dumbbell_press')
  ) then
    raise exception 'Adjustable-bench exercise remained after both benches were removed';
  end if;
  if not exists (
    select 1 from public.gym_store_exercise_ids('kanekin-fitness-gym:matsudo')
    where exercise_id = 'flat_dumbbell_press'
  ) then
    raise exception 'Flat-bench evidence was damaged by adjustable-bench removal';
  end if;
end;
$$;

rollback;
