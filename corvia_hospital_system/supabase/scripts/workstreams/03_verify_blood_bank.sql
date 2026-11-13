-- READ ONLY installation checks (database owner / SQL Editor).
select table_name from information_schema.tables
where table_schema='public' and table_name like 'corvia_bb_%' order by table_name;

select c.relname, c.relrowsecurity,
  has_table_privilege('authenticated',c.oid,'SELECT') as direct_read,
  has_table_privilege('authenticated',c.oid,'INSERT') as direct_insert,
  has_table_privilege('authenticated',c.oid,'UPDATE') as direct_update,
  has_table_privilege('authenticated',c.oid,'DELETE') as direct_delete
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relname like 'corvia_bb_%'
order by c.relname;
-- Expected: RLS true; all direct privileges false (RPC-only access).

select p.proname,p.prosecdef,
  has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as signed_in_execute,
  p.proconfig
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname like 'corvia_bb_%' order by p.proname;
-- Expected: security definer true, anon false, authenticated true, empty search_path.

select hospital_id,operating_mode,clinical_issue_enabled,
  clinical_authority_reference is not null as authority_recorded
from public.corvia_bb_settings;

select hospital_id,role,active,count(*) from public.corvia_bb_memberships
group by hospital_id,role,active order by hospital_id,role;

select table_name,action,count(*) as recorded_events
from corvia_bb_private.configuration_events group by table_name,action;

-- After this, use normal signed-in test accounts in the app. SQL Editor runs
-- with elevated authority and cannot establish real PostgREST/JWT access.
