"""Build a reviewed additive shared upgrade from the tested WS4 contracts.

Does not connect to any database. The generated SQL requires explicit owner review.
The internal legacy policy identifier remains stable for existing Flutter clients.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'supabase/scripts/ws4_dev'


def profile_hardening():
    """Shared profile permissions; never exempt an owner name in a trigger.

    Existing DEFINER functions keep their authorization checks and ownership.
    Their dependency graph still requires rehearsal against the target catalog.
    """
    return r'''
-- Refuse profile default/RLS drift instead of silently changing shared state.
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.profiles'::regclass
      AND relrowsecurity AND NOT relforcerowsecurity) OR
     (SELECT count(*) FROM pg_attribute a JOIN pg_attrdef d
        ON d.adrelid=a.attrelid AND d.adnum=a.attnum
      WHERE a.attrelid='public.profiles'::regclass AND
        ((a.attname IN ('role','user_type') AND pg_get_expr(d.adbin,d.adrelid)=$default$'patient'::text$default$)
         OR (a.attname='is_active' AND pg_get_expr(d.adbin,d.adrelid)='true')))<>3 THEN
    RAISE EXCEPTION 'Profile defaults or RLS differ from reviewed patient signup contract';
  END IF;
END $$;
-- Column ACLs protect authority independently of SECURITY DEFINER ownership.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.profiles FROM PUBLIC, anon, authenticated;
DO $$ DECLARE cols text; BEGIN
  SELECT string_agg(quote_ident(attname), ',') INTO cols FROM pg_attribute
    WHERE attrelid='public.profiles'::regclass AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE INSERT (%s), UPDATE (%s), REFERENCES (%s) ON public.profiles FROM PUBLIC,anon,authenticated',cols,cols,cols);
END $$;
GRANT INSERT(user_id,id_number,first_name,surname,email,address,phone_number,
  profile_picture_url,phone,date_of_birth,avatar_url,profile_complete)
  ON public.profiles TO authenticated;
-- PostgREST merge-duplicates includes the conflict key in its UPDATE list.
-- RLS below requires both old and new user_id to equal the authenticated UID.
GRANT UPDATE(user_id,id_number,first_name,surname,email,address,phone_number,
  profile_picture_url,phone,date_of_birth,avatar_url,profile_complete,updated_at)
  ON public.profiles TO authenticated;
CREATE POLICY ws4_shared_self_patient_registration ON public.profiles
  AS RESTRICTIVE FOR INSERT TO authenticated
  WITH CHECK(user_id=(SELECT auth.uid()) AND role='patient'
    AND user_type='patient' AND is_active IS TRUE);
CREATE POLICY ws4_shared_self_profile_update ON public.profiles
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING(user_id=(SELECT auth.uid())) WITH CHECK(user_id=(SELECT auth.uid()));
-- Fail closed if inherited privileges defeat the column restriction.
DO $$ DECLARE r text; c text; BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH c IN ARRAY ARRAY['role','user_type','is_active','id','created_at'] LOOP
      IF has_column_privilege(r,'public.profiles',c,'INSERT')
         OR has_column_privilege(r,'public.profiles',c,'UPDATE') THEN
        RAISE EXCEPTION 'Inherited profile authority privileges require review: % %',r,c;
      END IF;
    END LOOP;
  END LOOP;
END $$;
-- Replace only the audited unconditional legacy user_type blocker. Do not
-- change the shared function: another table might still use it.
DO $$ DECLARE existing record; BEGIN
  SELECT p.prosrc,p.oid,t.tgtype,t.tgenabled INTO existing
    FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='public.profiles'::regclass
      AND t.tgname='profiles_block_user_type_change' AND NOT t.tgisinternal;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Legacy profile trigger differs from reviewed definition';
  END IF;
  IF existing.oid<>to_regprocedure('public.block_user_type_change()')
     OR existing.tgtype<>19 OR existing.tgenabled<>'O'
     OR regexp_replace(existing.prosrc,'\s','','g') <>
        regexp_replace($body$BEGIN
          IF NEW.user_type != OLD.user_type THEN
            RAISE EXCEPTION 'user_type cannot be changed by the client';
          END IF;
          RETURN NEW;
        END;$body$,'\s','','g') THEN
    RAISE EXCEPTION 'Legacy profile trigger differs from reviewed definition';
  END IF;
END $$;
CREATE FUNCTION ws4_dev_private.guard_profile_user_type() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NEW.user_type IS DISTINCT FROM OLD.user_type
     AND NOT has_column_privilege(current_user,'public.profiles','user_type','UPDATE') THEN
    RAISE EXCEPTION 'Profile authority fields are server controlled' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER profiles_block_user_type_change ON public.profiles;
CREATE TRIGGER profiles_block_user_type_change BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_profile_user_type();
-- The audited patient DEFINER RPC used to reactivate any caller's profile.
-- Patch only the exact reviewed definition, retaining its owner and signature.
DO $$ DECLARE fn regprocedure; definition text; original text; BEGIN
  fn:=to_regprocedure('public.corvia_upsert_my_patient_profile(text,text,text,date,text,text,text,text,text,text,text,text,text)');
  IF fn IS NOT NULL THEN
    definition:=replace(pg_get_functiondef(fn),E'\r\n',E'\n');
    IF md5(regexp_replace(definition,'\s','','g'))<>'38e423d7aba9aeac27247fec671769d8' THEN
      RAISE EXCEPTION 'Patient profile RPC differs from reviewed 12 October definition';
    END IF;
    original:=definition;
    definition:=replace(definition,
      E'  select email\n  into v_email',
      E'  PERFORM 1 FROM public.profiles WHERE user_id=v_user_id FOR UPDATE;\n' ||
      '  IF EXISTS(SELECT 1 FROM public.profiles WHERE user_id=v_user_id AND is_active IS NOT TRUE) THEN ' ||
      'RAISE EXCEPTION ''Inactive profile requires administrator review'' USING ERRCODE=''42501''; END IF;' ||
      E'\n  select email\n  into v_email');
    definition:=replace(definition,
      E'    role = coalesce(public.profiles.role, ''patient''),\n    is_active = true,',
      E'    role = public.profiles.role,\n    is_active = public.profiles.is_active,');
    -- RETURNS TABLE names are PL/pgSQL variables; qualify the patient lookup.
    definition:=replace(definition,
      E'  select id, patient_number\n  into v_patient_id, v_patient_number\n  from public.patients\n  where profile_id = v_profile_id',
      E'  select patient.id, patient.patient_number\n  into v_patient_id, v_patient_number\n  from public.patients patient\n  where patient.profile_id = v_profile_id');
    IF definition=original OR position('PERFORM 1 FROM public.profiles' in definition)=0
      OR position('is_active = public.profiles.is_active' in definition)=0 THEN
      RAISE EXCEPTION 'Patient profile RPC patch did not match';
    END IF;
    EXECUTE definition;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon',fn);
  END IF;
END $$;
'''

def build():
    core=(SOURCE/'001_secure_core.sql').read_text(encoding='utf-8')
    # Replace fresh-bootstrap assumptions, never execute the dev bootstrap against shared data.
    start=core.index('DO $$'); end=core.index('CREATE SCHEMA',start)
    core=core[:start]+'''DO $$
BEGIN
  IF current_user<>'postgres' OR current_setting('corvia.ws4_shared_review',true) IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'Database owner must review preflight, backups, role compatibility and rollout, then explicitly approve this transaction';
  END IF;
  IF to_regclass('public.profiles') IS NULL OR to_regclass('public.incidents') IS NULL OR to_regnamespace('ws4_private') IS NOT NULL THEN
    RAISE EXCEPTION 'Expected existing Corvia schema missing or upgrade already installed';
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='incidents' AND column_name IN ('version','organisation_id','location_source')) THEN
    RAISE EXCEPTION 'Conflicting incident extension; compare the current schema before migration';
  END IF;
  IF EXISTS(SELECT 1 FROM public.incidents WHERE user_id IS NULL OR status IS NULL OR status NOT IN ('pending','in_progress','resolved','cancelled')
    OR latitude IS NULL OR longitude IS NULL OR NOT(latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)) THEN
    RAISE EXCEPTION 'Legacy incidents require explicit data review; no records have been changed';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='register_auth_user_temp' AND has_function_privilege('anon',p.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'Backend owner must first resolve the exported anonymous privileged registration function';
  END IF;
END $$;

'''+core[end:]
    start=core.index('CREATE TABLE public.profiles');end=core.index('-- These are isolated',start)
    core=core[:start]+core[end:]
    start=core.index('CREATE TABLE public.incidents');end=core.index('CREATE INDEX ws4_dev_incidents_scope',start)
    core=core[:start]+'''-- Existing incident rows retain their IDs and data. No organisation is guessed.
ALTER TABLE public.incidents
  ADD COLUMN organisation_id uuid REFERENCES ws4_dev_private.organisations(id),
  ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
-- Unmapped legacy rows are withheld from dispatch. Owner must agree and backfill
-- routing separately; there is deliberately no fake historical audit backfill.
'''+core[end:]
    core=core.replace("label text NOT NULL CHECK (label LIKE 'Synthetic %')","label text NOT NULL CHECK (btrim(label)<>'')")
    core=core.replace('CREATE FUNCTION public.corvia_is_dispatch_operator()', 'CREATE OR REPLACE FUNCTION public.corvia_is_dispatch_operator()')
    core=core.replace('CREATE FUNCTION public.corvia_dispatch_accept_incident(', 'CREATE OR REPLACE FUNCTION public.corvia_dispatch_accept_incident(')
    core=core.replace('CREATE FUNCTION public.corvia_dispatch_access_context()', 'CREATE OR REPLACE FUNCTION public.corvia_dispatch_access_context()')
    # The dev trigger assumes postgres owns every writer; this is false on hosted
    # Corvia. Use explicit client column privileges with restrictive owning RLS.
    start=core.index('CREATE FUNCTION ws4_dev_private.guard_profile()')
    end=core.index('CREATE FUNCTION ws4_dev_private.guard_incident()',start)
    core=core[:start]+profile_hardening()+core[end:]
    # Preserve existing hospital profile read grants and policies.
    core=core.replace('REVOKE ALL ON public.profiles, public.incidents', 'REVOKE ALL ON public.incidents')
    core=core.replace('GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;', '')
    marker='-- Revoke explicit defaults'
    index=core.index(marker)
    core=core[:index]+'''-- Existing permissive policies cannot widen the new WS4 incident scope.
CREATE POLICY ws4_shared_scope ON public.incidents AS RESTRICTIVE FOR ALL TO authenticated
USING ((user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active())) OR ws4_dev_private.in_scope(organisation_id))
WITH CHECK ((user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active())) OR ws4_dev_private.in_scope(organisation_id));
-- Table-level revocation alone does not remove old column privileges.
DO $$ DECLARE cols text; BEGIN
  SELECT string_agg(quote_ident(attname),',') INTO cols FROM pg_attribute
    WHERE attrelid='public.incidents'::regclass AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE ALL (%s) ON public.incidents FROM PUBLIC,anon,authenticated,service_role',cols);
END $$;
'''+core[index:]
    files=[core]+[(SOURCE/name).read_text(encoding='utf-8') for name in ('002_patient_intake.sql','003_cancel_and_history.sql','004_dispatch_operations.sql','005_response_workflow.sql')]
    pieces=[]
    for i,sql in enumerate(files):
        sql=re.sub(r'^--[^\n]*\n','',sql,flags=re.M)
        sql=re.sub(r'^BEGIN;\s*|^COMMIT;\s*','',sql,flags=re.M)
        sql=sql.replace('ws4_dev_private','ws4_private')
        sql=sql.replace('AND synthetic_only AND','AND NOT synthetic_only AND')
        sql=sql.replace('DEFAULT true CHECK (synthetic_only)','DEFAULT false CHECK (NOT synthetic_only)')
        sql=sql.replace('Owned synthetic','Reviewed shared').replace('OWNED SYNTHETIC WS4 DEVELOPMENT ONLY','SHARED CONTRACT DELTA')
        pieces.append(f'-- Contract section {i+1}\n'+sql)
    return '''-- GENERATED by tools/build_ws4_shared_upgrade.py. DO NOT hand edit.
-- Existing Corvia upgrade candidate, not a reset. Owner review and schema rehearsal required.
-- See README.md and run preflight.sql first. No account/route/member is auto-provisioned.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
'''+ '\n'.join(pieces)+ '''
-- CREATE OR REPLACE retains the old owner; privileged RPCs must use the reviewed owner.
ALTER FUNCTION public.corvia_is_dispatch_operator() OWNER TO postgres;
ALTER FUNCTION public.corvia_dispatch_accept_incident(bigint) OWNER TO postgres;
ALTER FUNCTION public.corvia_dispatch_access_context() OWNER TO postgres;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_admin') THEN
    GRANT EXECUTE ON FUNCTION public.corvia_is_dispatch_operator() TO supabase_admin;
  END IF;
END $$;
COMMIT;
'''

if __name__=='__main__':
    path=ROOT/'supabase/scripts/ws4_release/001_shared_upgrade.sql'
    path.write_text(build(),encoding='utf-8')
    print('Generated '+str(path))
