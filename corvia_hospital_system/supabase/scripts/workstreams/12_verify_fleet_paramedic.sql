-- Read-only verification after 11_install_fleet_paramedic.sql.
select
  to_regprocedure('public.corvia_ems_access()') is not null as has_workspace_access,
  to_regprocedure('public.corvia_ems_open(uuid,text)') is not null as has_sessions,
  to_regprocedure('public.corvia_ems_workspace(uuid,uuid,bigint)') is not null as has_workspace,
  to_regprocedure('public.corvia_ems_command(uuid,uuid,uuid,text,jsonb)') is not null as has_commands;

select p.proname as function_name,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and (p.proname like 'corvia_ems_%' or p.proname like 'corvia_ws6_actual_%')
order by p.proname;
-- Only access/open/workspace/command should be executable by authenticated.
-- Anonymous must be false everywhere.

select c.relname as table_name,c.relrowsecurity as rls_enabled,
 has_table_privilege('authenticated',c.oid,'SELECT') as direct_client_read
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
 and (c.relname like 'corvia_ems_%' or c.relname like 'corvia_ws6_%')
order by c.relname;
-- RLS should be true and direct_client_read false.

select h.name as hospital,
 (select count(*) from public.corvia_ws6_units_actual t where t.hospital_id=h.id) as vehicles,
 (select count(*) from public.corvia_ws6_ems_members t where t.hospital_id=h.id) as personnel,
 (select count(*) from public.corvia_ws6_crews t where t.hospital_id=h.id and crew_status='Active' and end_datetime>now()) as active_crews,
 (select count(*) from public.corvia_ws6_incidents_actual t where t.hospital_id=h.id) as incidents,
 (select count(*) from public.corvia_ws6_receiving_facilities t where t.hospital_id=h.id) as receiving_facilities
from public.hospitals h where h.id='c6c7adb9-be6b-4dd6-ac47-17becd153df6'::uuid;
