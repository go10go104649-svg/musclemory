-- Supabase auth.users.email is varchar(255), but this RPC returns text.
-- Preserve membership checks, email visibility, and existing function grants.
begin;
create or replace function public.tenant_members(p_tenant uuid) returns table(tenant_id uuid,user_id uuid,is_admin boolean,is_trainer boolean,status text,display_name text,email text) language plpgsql stable security definer set search_path='' as $$
begin
 if not public.tenant_has_role(p_tenant) then raise exception 'Active membership required'; end if;
 return query select m.tenant_id,m.user_id,m.is_admin,m.is_trainer,m.status,coalesce(p.display_name,u.email,'Member'),case when public.tenant_has_role(p_tenant,'admin') then u.email::text end
 from public.tenant_memberships m join auth.users u on u.id=m.user_id left join public.trainer_profiles p on p.user_id=m.user_id
 where m.tenant_id=p_tenant and (m.status='active' or public.tenant_has_role(p_tenant,'admin'));
end $$;
commit;
