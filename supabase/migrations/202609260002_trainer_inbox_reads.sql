-- Keep the trainer's menu/comment rows as the source of truth. A read marker
-- belongs to the currently linked client account, not to the trainer.
begin;
alter table public.tenant_menus
  add column client_read_by uuid references auth.users(id),
  add column client_read_at timestamptz;
alter table public.tenant_comments
  add column client_read_by uuid references auth.users(id),
  add column client_read_at timestamptz;

create function public.tenant_inbox_unread_count() returns integer
language sql stable security definer set search_path = '' as $$
  select (
    (select count(*) from public.tenant_menus m
      join public.tenant_clients c on c.tenant_id=m.tenant_id and c.id=m.client_id
      where c.linked_user_id=auth.uid() and c.status='active'
        and m.status<>'canceled'
        and (m.client_read_by is distinct from auth.uid()
          or m.client_read_at is null or m.client_read_at < m.updated_at))
    +
    (select count(*) from public.tenant_comments n
      join public.tenant_clients c on c.tenant_id=n.tenant_id and c.id=n.client_id
      where c.linked_user_id=auth.uid() and c.status='active'
        and n.shared_with_client
        and (n.client_read_by is distinct from auth.uid()
          or n.client_read_at is null or n.client_read_at < n.updated_at))
  )::integer
$$;

create function public.tenant_mark_inbox_read(
  p_menu_ids uuid[] default '{}', p_comment_ids uuid[] default '{}'
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.tenant_menus m
    set client_read_by=auth.uid(), client_read_at=clock_timestamp()
    where m.id=any(p_menu_ids) and m.status<>'canceled'
      and exists(select 1 from public.tenant_clients c
        where c.tenant_id=m.tenant_id and c.id=m.client_id
          and c.linked_user_id=auth.uid() and c.status='active');
  update public.tenant_comments n
    set client_read_by=auth.uid(), client_read_at=clock_timestamp()
    where n.id=any(p_comment_ids) and n.shared_with_client
      and exists(select 1 from public.tenant_clients c
        where c.tenant_id=n.tenant_id and c.id=n.client_id
          and c.linked_user_id=auth.uid() and c.status='active');
end $$;

revoke all on function public.tenant_inbox_unread_count() from public, anon;
revoke all on function public.tenant_mark_inbox_read(uuid[],uuid[]) from public, anon;
grant execute on function public.tenant_inbox_unread_count() to authenticated;
grant execute on function public.tenant_mark_inbox_read(uuid[],uuid[]) to authenticated;
-- Clients retain SELECT-only table grants. The RPC is the sole read-marker writer.
commit;
