-- READ ONLY. Run on the intended shared project and return the single JSON row.
-- No Auth records, keys, patient details, messages or coordinates are exported.
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'database_version',current_setting('server_version'),
  'columns',(SELECT jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type,'nullable',is_nullable) ORDER BY table_name,ordinal_position)
    FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('profiles','incidents','incident_messages','incident_responder_assignments','responders')),
  'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname='public' AND tablename IN ('profiles','incidents','incident_messages','incident_responder_assignments')),
  'routines',(SELECT jsonb_agg(jsonb_build_object('name',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,
    'definition_hash',md5(pg_get_functiondef(p.oid)),'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
    'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),'acl',p.proacl::text))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f'
    AND (p.proname LIKE '%incident%' OR p.proname LIKE '%dispatch%' OR p.proname LIKE '%register_auth%')),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,'definition',pg_get_triggerdef(t.oid)))
    FROM pg_trigger t WHERE NOT t.tgisinternal AND t.tgrelid IN ('public.profiles'::regclass,'public.incidents'::regclass)),
  'grants',(SELECT jsonb_agg(to_jsonb(g)) FROM information_schema.role_table_grants g WHERE table_schema='public' AND table_name IN ('profiles','incidents')),
  'column_grants',(SELECT jsonb_agg(to_jsonb(g)) FROM information_schema.column_privileges g WHERE table_schema='public' AND table_name='incidents'),
  'publications',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_publication_tables p WHERE schemaname='public' AND tablename LIKE '%incident%'),
  'existing_incident_count',(SELECT count(*) FROM public.incidents),
  'invalid_legacy_incident_count',(SELECT count(*) FROM public.incidents WHERE user_id IS NULL OR status IS NULL OR status NOT IN ('pending','in_progress','resolved','cancelled')
    OR latitude IS NULL OR longitude IS NULL OR NOT(latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)),
  'upgrade_present',to_regnamespace('ws4_private') IS NOT NULL
) AS ws4_preflight;
ROLLBACK;
