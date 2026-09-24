do $$
declare
  missing_count integer;
begin
  select count(*) into missing_count
  from (
    values
      ('fit-place24:fp_eq_037d2725574b', 'linear_row'),
      ('fit-place24:fp_eq_b962f153802e', 'linear_row'),
      ('fit-place24:fp_eq_3ffb97ab19d3', 'high_row'),
      ('fit-place24:fp_eq_e28aa6bb657a', 'back_extension'),
      ('fit-place24:fp_eq_e28aa6bb657a', 'weighted_back_extension'),
      ('fit-place24:fp_eq_e2f90d4521d0', 'machine_hip_thrust'),
      ('fit-place24:fp_eq_9cbae3e29b25', 'machine_arm_curl'),
      ('fit-place24:fp_eq_6ac44b958236', 'back_extension_machine'),
      ('fit-place24:fp_eq_c2e8b4cbe71b', 'machine_hip_thrust'),
      ('fit-place24:fp_eq_2069c8ac3ff1', 'lat_pulldown'),
      ('fit-place24:fp_eq_c563b0cde41a', 'pec_fly'),
      ('fit-place24:fp_eq_c563b0cde41a', 'rear_delt'),
      ('fit-place24:fp_eq_0a13c23b47c0', 'lat_pulldown'),
      ('fit-place24:fp_eq_09d623796663', 'seated_leg_curl')
  ) as expected(equipment_id, exercise_id)
  where not exists (
    select 1
    from public.equipment_exercise_mapping actual
    where actual.equipment_id = expected.equipment_id
      and actual.exercise_id = expected.exercise_id
  );

  if missing_count <> 0 then
    raise exception 'missing % resolved ambiguous mappings', missing_count;
  end if;
end;
$$;
