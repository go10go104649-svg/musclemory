-- Keep the five-argument tenant_record RPC for installed clients. The new
-- overload writes the session-wide trainer comment into the same workout row.
begin;
create function public.tenant_record(
  p_tenant uuid,
  p_client uuid,
  p_request uuid,
  p_date timestamptz,
  p_sets jsonb,
  p_note text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  record_id uuid;
  clean_note text := trim(coalesce(p_note, ''));
begin
  if length(clean_note) > 10000 then
    raise exception 'Session comment is too long';
  end if;
  -- The original RPC checks tenant membership, assignment, consent, sets,
  -- and the request ID under the tenant lock before this update can run.
  record_id := public.tenant_record(
    p_tenant, p_client, p_request, p_date, p_sets
  );
  update public.workouts
    set note = clean_note, updated_at = now()
    where id = record_id and tenant_id = p_tenant
      and tenant_client_id = p_client and record_source = 'trainer'
      and note is distinct from clean_note;
  return record_id;
end $$;
revoke all on function public.tenant_record(uuid,uuid,uuid,timestamptz,jsonb,text)
  from public, anon, authenticated;
grant execute on function public.tenant_record(uuid,uuid,uuid,timestamptz,jsonb,text)
  to authenticated;
commit;
