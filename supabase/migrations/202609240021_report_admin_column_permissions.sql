begin;
-- Projects may have default table privileges granting UPDATE on new tables.
-- Explicitly remove those before granting the limited review columns.
revoke update on public.gym_exercise_reports,public.gym_equipment_reports from anon,authenticated;
grant update(status,admin_note) on public.gym_exercise_reports,public.gym_equipment_reports to authenticated;
commit;
