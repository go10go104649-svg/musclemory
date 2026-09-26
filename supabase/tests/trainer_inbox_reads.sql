-- Run after 202609260002. The complete test transaction is rolled back.
begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if;
 raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id,email,email_confirmed_at)
select ('31000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 'inbox'||n||'@test.invalid',now() from generate_series(1,3)n;
set local role authenticated;
do $$
declare
  tenant uuid;
  client_a uuid;
  client_b uuid;
  menu_a uuid;
  menu_b uuid;
  comment_a uuid;
  comment_b uuid;
  private_note uuid;
  invite_a uuid;
  invite_b uuid;
  items jsonb := '[{"exercise_id":"bench_press","exercise_name":"Bench","body_part":"胸","equipment":"barbell","record_type":"weightReps","set_values":[{"weight":20,"reps":10}]}]';
begin
  perform set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
  tenant := public.tenant_create('Inbox');
  client_a := (public.tenant_mutate(tenant,'client','{"name":"A"}')->>'id')::uuid;
  client_b := (public.tenant_mutate(tenant,'client','{"name":"B"}')->>'id')::uuid;
  menu_a := (public.tenant_mutate(tenant,'menu',jsonb_build_object('client_id',client_a,'name','A menu','items',items))->>'id')::uuid;
  menu_b := (public.tenant_mutate(tenant,'menu',jsonb_build_object('client_id',client_b,'name','B menu','items',items))->>'id')::uuid;
  comment_a := public.tenant_save_comment(tenant,client_a,'A comment');
  comment_b := public.tenant_save_comment(tenant,client_b,'B comment');
  private_note := (public.tenant_mutate(tenant,'comment',jsonb_build_object('client_id',client_a,'body','Private note'))->>'id')::uuid;
  invite_a := (public.tenant_mutate(tenant,'client_invite',jsonb_build_object('client_id',client_a))->>'id')::uuid;
  invite_b := (public.tenant_mutate(tenant,'client_invite',jsonb_build_object('client_id',client_b))->>'id')::uuid;

  perform set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000002',true);
  perform public.trainer_accept_invite(invite_a,'A',false,false);
  perform pg_temp.ok(public.tenant_inbox_unread_count()=2,'A sees a menu and shared comment');
  perform public.tenant_mark_inbox_seen(jsonb_build_object(menu_a,1),'{}');
  perform pg_temp.ok(public.tenant_inbox_unread_count()=1,'menu read leaves comment unread');
  perform public.tenant_mark_inbox_seen('{}',jsonb_build_object(comment_a,1));
  perform pg_temp.ok(public.tenant_inbox_unread_count()=0,'both reads persist server-side');
  perform pg_temp.ok(pg_temp.denied(format('update public.tenant_menus set client_read_at=now() where id=%L',menu_a)),'client cannot edit read marker directly');
  perform public.tenant_mark_inbox_seen(jsonb_build_object(menu_b,1),jsonb_build_object(comment_b,1,private_note,1));
  perform pg_temp.ok(public.tenant_inbox_unread_count()=0,'foreign/private IDs are ignored');

  perform set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000003',true);
  perform public.trainer_accept_invite(invite_b,'B',false,false);
  perform pg_temp.ok(public.tenant_inbox_unread_count()=2,'B unread independent of A');
  perform public.tenant_mark_inbox_seen(jsonb_build_object(menu_a,1),jsonb_build_object(comment_a,1));
  perform pg_temp.ok(public.tenant_inbox_unread_count()=2,'B cannot mark A items read');

  perform set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
  perform public.tenant_mutate(tenant,'menu',jsonb_build_object('id',menu_a,'client_id',client_a,'version',1,'name','A edited','schedule','single','items',items));
  perform public.tenant_save_comment(tenant,client_a,'A edited comment',p_id=>comment_a,p_version=>1);
  perform set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000002',true);
  perform pg_temp.ok(public.tenant_inbox_unread_count()=2,'trainer edits become unread again');
  perform public.tenant_mark_inbox_seen(jsonb_build_object(menu_a,1),jsonb_build_object(comment_a,1));
  perform pg_temp.ok(public.tenant_inbox_unread_count()=2,'stale loaded versions do not mark edits read');
  perform public.tenant_mark_inbox_seen(jsonb_build_object(menu_a,2),jsonb_build_object(comment_a,2));
  perform pg_temp.ok(public.tenant_inbox_unread_count()=0,'edited items can be read again');
end $$;
set local role anon;
select pg_temp.ok(pg_temp.denied('select public.tenant_inbox_unread_count()'),'anonymous cannot count');
select pg_temp.ok(pg_temp.denied('select public.tenant_mark_inbox_seen()'),'anonymous cannot mark read');
rollback;
