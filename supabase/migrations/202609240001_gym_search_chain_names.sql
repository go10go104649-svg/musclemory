begin;
-- Search aliases are data, so other chains need no application changes.
alter table public.gym_chains add column if not exists search_aliases text[] not null default '{}';
update public.gym_chains set search_aliases=array['フィットプレイス','フィットプレイス24'] where id='fit-place24';
create or replace function public.search_gym_stores(search_query text default '', page_offset integer default 0)
returns table(id text,chain_id text,chain_name text,name text,prefecture text,city text,address text,station text,equipment_status text)
language sql stable security invoker set search_path='' as $$
 select s.id,s.chain_id,c.name,s.name,s.prefecture,s.city,s.address,s.station,s.equipment_status
 from public.gym_stores s join public.gym_chains c on c.id=s.chain_id
 where s.active and not exists (
   select 1 from regexp_split_to_table(lower(normalize(trim(coalesce(search_query,'')),NFKC)), '\s+') as q(term)
   where q.term<>'' and strpos(
     regexp_replace(lower(normalize(concat_ws(' ',c.name,array_to_string(c.search_aliases,' '),s.name,s.city,s.station),NFKC)), '\s+', '', 'g'),
     q.term
   )=0
 )
 order by s.name,s.id limit 30 offset greatest(0,least(page_offset,100000));
$$;
commit;
