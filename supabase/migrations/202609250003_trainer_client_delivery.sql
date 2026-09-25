-- Both apps read the same tenant rows. Existing staff-only notes stay private.
begin;
alter table public.tenant_comments
 add column shared_with_client boolean not null default false,
 add column updated_at timestamptz not null default now(),
 add column edited_by uuid references auth.users(id),
 add column version integer not null default 1;
update public.tenant_comments set updated_at=created_at, edited_by=created_by;
alter table public.tenant_comments alter column edited_by set not null;
-- Keep the older tenant_mutate('comment') RPC compatible and private.
create function public.tenant_comment_author() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.edited_by is null then new.edited_by=new.created_by; end if;
 return new;
end $$;
create trigger tenant_comment_author before insert on public.tenant_comments
for each row execute function public.tenant_comment_author();

create function public.tenant_is_client(t uuid,c uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tenant_clients x where x.tenant_id=t
 and x.id=c and x.linked_user_id=auth.uid() and x.status='active')
$$;
revoke all on function public.tenant_is_client(uuid,uuid) from public,anon;
grant execute on function public.tenant_is_client(uuid,uuid) to authenticated;
revoke all on function public.tenant_comment_author() from public,anon,authenticated;

drop policy menu_read on public.tenant_menus;
create policy menu_read on public.tenant_menus for select to authenticated using(
 public.tenant_can_coach(tenant_id,client_id) or
 (status<>'canceled' and public.tenant_is_client(tenant_id,client_id)));
-- Existing exercise_read and sets_read follow the parent RLS; no broad child policy.
drop policy comments_read on public.tenant_comments;
create policy comments_read on public.tenant_comments for select to authenticated using(
 public.tenant_can_coach(tenant_id,client_id) or
 (shared_with_client and public.tenant_is_client(tenant_id,client_id)));

create function public.tenant_save_comment(
 p_tenant uuid,p_client uuid,p_body text,
 p_id uuid default null,p_version integer default null,p_menu uuid default null,
 p_date date default null,p_shared boolean default true,p_delete boolean default false
) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.tenant_comments; result uuid;
begin
 -- Same lock as assignments, consent revocation and other tenant mutations.
 perform 1 from public.tenants where id=p_tenant for update;
 if not found or not public.tenant_can_coach(p_tenant,p_client) then
  raise exception 'Assigned trainer required';
 end if;
 if p_id is not null then
  select * into r from public.tenant_comments where id=p_id
   and tenant_id=p_tenant and client_id=p_client for update;
  if not found or r.version is distinct from p_version then
   raise exception 'Comment changed; reload before editing';
  end if;
  if p_delete then
   delete from public.tenant_comments where id=r.id;
  else
   update public.tenant_comments set body=trim(p_body),shared_with_client=p_shared,
    updated_at=clock_timestamp(),edited_by=auth.uid(),version=version+1 where id=r.id;
  end if;
  return r.id;
 end if;
 if p_delete then raise exception 'Comment ID required'; end if;
 if p_menu is not null and not exists(select 1 from public.tenant_menus
  where id=p_menu and tenant_id=p_tenant and client_id=p_client) then
  raise exception 'Menu/client mismatch';
 end if;
 insert into public.tenant_comments(tenant_id,client_id,menu_id,workout_date,body,
  created_by,edited_by,shared_with_client)
 values(p_tenant,p_client,p_menu,p_date,trim(p_body),auth.uid(),auth.uid(),p_shared)
 returning id into result;
 return result;
end $$;
revoke all on function public.tenant_save_comment(uuid,uuid,text,uuid,integer,uuid,date,boolean,boolean) from public,anon;
grant execute on function public.tenant_save_comment(uuid,uuid,text,uuid,integer,uuid,date,boolean,boolean) to authenticated;
-- No INSERT/UPDATE/DELETE grants or policies are added for clients.
commit;
