-- READ ONLY. Return definitions to reconcile the existing lab verification flow.
-- Does not publish results, change verification, or return patient records.
select p.oid::regprocedure as function_signature,pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind='f'
  and (p.proname='corvia_hospital_complete_lab_result'
    or (p.proname ilike '%lab%' and
      (p.proname ilike '%verif%' or p.proname ilike '%submit%' or p.proname ilike '%release%')))
order by p.proname;

select t.tgname,pg_get_triggerdef(t.oid) as trigger_definition,
  pg_get_functiondef(t.tgfoid) as function_definition
from pg_trigger t where t.tgrelid='public.lab_results'::regclass and not t.tgisinternal;
