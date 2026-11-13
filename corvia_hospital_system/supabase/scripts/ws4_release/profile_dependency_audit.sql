-- READ ONLY metadata export for the remaining compatibility gate.
-- No patient, account, message, credential or clinical rows are read.
-- This is not a backup. Review function bodies for embedded secrets before sharing.
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'version',current_setting('server_version'),
  'tables',(SELECT jsonb_agg(jsonb_build_object(
    'name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),
    'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
    'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,
      'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
      'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl::text) ORDER BY a.attnum)
      FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
    'constraints',(SELECT jsonb_agg(pg_get_constraintdef(k.oid)) FROM pg_constraint k WHERE k.conrelid=c.oid),
    'indexes',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid)) FROM pg_index i WHERE i.indrelid=c.oid),
    'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE p.schemaname=n.nspname AND p.tablename=c.relname),
    'triggers',(SELECT jsonb_agg(jsonb_build_object('ddl',pg_get_triggerdef(t.oid),
      'enabled',t.tgenabled,'function',pg_get_functiondef(t.tgfoid)))
      FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)))
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relname=ANY(ARRAY[
      'profiles','incidents','patients','hospitals','hospital_admins','departments',
      'doctors','hospital_nurses','pharmacists','hospital_staff',
      'corvia_hospital_staff_accounts','corvia_hospital_reception_staff',
      'lab_organizations','lab_worker_accounts','hospital_lab_admin_accounts',
      'private_lab_admin_accounts','hospital_lab_access_audit','corvia_ops_memberships'])),
  'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
    'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,
    'definition',pg_get_functiondef(p.oid)))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.prokind='f' AND ((n.nspname='auth' AND p.proname='uid') OR
      (n.nspname='public' AND (p.proname LIKE 'corvia_admin_%'
        OR p.proname LIKE 'corvia_%lab_admin%'
        OR p.proname LIKE 'corvia_ems_%' OR p.proname LIKE 'corvia_ops_%'
        OR p.proname IN ('doctor_can_view_linked_patient_profile',
          'corvia_pharmacist_can_access_profile','corvia_upsert_my_patient_profile',
          'register_auth_user_temp','block_user_type_change','set_updated_at'))))),
  'role_memberships',(SELECT jsonb_agg(jsonb_build_object(
    'member',pg_get_userbyid(member),'role',pg_get_userbyid(roleid))) FROM pg_auth_members)
) AS ws4_profile_dependency_audit;
ROLLBACK;
