-- Read-only metadata, no patient rows, credentials or auth tokens.
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'database_version', version(),
  'installation', (SELECT to_jsonb(i) FROM ws4_dev_private.installation i),
  'tables', (SELECT jsonb_agg(jsonb_build_object(
    'schema',n.nspname,'table',c.relname,'rls',c.relrowsecurity,'owner',pg_get_userbyid(c.relowner))
    ORDER BY n.nspname,c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE (n.nspname='ws4_dev_private' OR (n.nspname='public' AND c.relname IN ('profiles','incidents')))
      AND c.relkind='r'),
  'policies', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.schemaname,p.tablename,p.policyname)
    FROM pg_policies p WHERE p.schemaname='ws4_dev_private'
      OR (p.schemaname='public' AND p.tablename IN ('profiles','incidents'))),
  'grants', (SELECT jsonb_agg(to_jsonb(g) ORDER BY g.table_schema,g.table_name,g.grantee,g.privilege_type)
    FROM information_schema.table_privileges g WHERE g.table_schema='ws4_dev_private'
      OR (g.table_schema='public' AND g.table_name IN ('profiles','incidents'))),
  'column_grants', (SELECT jsonb_agg(to_jsonb(g) ORDER BY g.table_name,g.column_name,g.grantee,g.privilege_type)
    FROM information_schema.column_privileges g WHERE g.table_schema='public'
      AND g.table_name IN ('profiles','incidents') AND g.grantee IN ('anon','authenticated','service_role')),
  'functions', (SELECT jsonb_agg(jsonb_build_object(
      'signature',p.oid::regprocedure::text,'definer',p.prosecdef,'config',p.proconfig,
      'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text)
      ORDER BY n.nspname,p.proname)
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='ws4_dev_private' OR (n.nspname='public' AND p.proname LIKE 'corvia_%'))
) AS ws4_dev_verification;
ROLLBACK;
