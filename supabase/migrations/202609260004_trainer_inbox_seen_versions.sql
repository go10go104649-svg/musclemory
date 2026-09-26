-- Mark only the exact versions successfully loaded by the client UI.
begin;
create function public.tenant_mark_inbox_seen(
  p_menu_versions jsonb default '{}', p_comment_versions jsonb default '{}'
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.tenant_menus m
    set client_read_by=auth.uid(), client_read_at=clock_timestamp(),
        client_read_version=m.version
    from jsonb_each_text(p_menu_versions) x
    where m.id=x.key::uuid and m.version=x.value::integer
      and m.status<>'canceled'
      and exists(select 1 from public.tenant_clients c
        where c.tenant_id=m.tenant_id and c.id=m.client_id
          and c.linked_user_id=auth.uid() and c.status='active');
  update public.tenant_comments n
    set client_read_by=auth.uid(), client_read_at=clock_timestamp(),
        client_read_version=n.version
    from jsonb_each_text(p_comment_versions) x
    where n.id=x.key::uuid and n.version=x.value::integer
      and n.shared_with_client
      and exists(select 1 from public.tenant_clients c
        where c.tenant_id=n.tenant_id and c.id=n.client_id
          and c.linked_user_id=auth.uid() and c.status='active');
end $$;
revoke all on function public.tenant_mark_inbox_seen(jsonb,jsonb) from public, anon;
grant execute on function public.tenant_mark_inbox_seen(jsonb,jsonb) to authenticated;
drop function public.tenant_mark_inbox_read(uuid[],uuid[]);
commit;
