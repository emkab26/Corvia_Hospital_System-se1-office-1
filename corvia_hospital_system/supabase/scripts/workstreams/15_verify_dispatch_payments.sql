-- Read-only. Run before installation to choose missing packages, and again afterward.
select
 to_regclass('public.corvia_payment_attempts') is not null as payment_base_installed,
 to_regprocedure('public.corvia_payment_escalate(uuid,text,boolean)') is not null as billing_reviews_installed,
 to_regprocedure('public.corvia_ems_command(uuid,uuid,uuid,text,jsonb)') is not null as paramedic_workspace_installed,
 to_regprocedure('public.corvia_ops_eligibility(uuid,bigint,text)') is not null as fleet_dispatch_upgrade_installed,
 to_regclass('public.corvia_ops_readiness') is not null as fleet_inspections_installed,
 to_regclass('public.corvia_ops_faults') is not null as fleet_fault_history_installed,
 to_regclass('public.corvia_ops_messages') is not null as incident_messages_installed;

select p.proname as function_name,
 has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
 has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and
 (p.proname like 'corvia_ops_%' or p.proname in
 ('corvia_ems_command','corvia_ems_workspace','corvia_ems_command_core','corvia_ems_workspace_core','corvia_payment_escalate'))
order by p.proname;
-- Only corvia_ems_command / corvia_ems_workspace / corvia_payment_escalate should
-- show authenticated_execute=true here. All anonymous_execute must be false.

select c.relname as table_name,c.relrowsecurity as rls_enabled,
 has_table_privilege('authenticated',c.oid,'INSERT') as client_insert,
 has_table_privilege('authenticated',c.oid,'UPDATE') as client_update,
 has_table_privilege('authenticated',c.oid,'DELETE') as client_delete
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
 and (c.relname like 'corvia_ops_%' or c.relname='corvia_payment_reviews')
order by c.relname;
-- RLS true; all direct client mutation columns false.

-- Installation checks do not prove account permissions, provider connectivity,
-- clinical acceptance or real records. Use signed-in Flutter accounts afterward.
