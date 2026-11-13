-- WS4 SYNTHETIC DEVELOPMENT ONLY. Not a migration for an existing Corvia DB.
-- Target: Jandre's corvia-ws4-dev. No ER24/Fleet/clinical integration implied.
-- Review README.md here before applying. The transaction refuses existing app data.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Bootstrap requires the project database owner';
  END IF;
  IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'Supabase Auth prerequisite missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'ws4_dev_private')
     OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f'))
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public' AND p.proname LIKE 'corvia_%') THEN
    RAISE EXCEPTION 'Fresh development database required; existing objects preserved';
  END IF;
END $$;

CREATE SCHEMA ws4_dev_private;
REVOKE ALL ON SCHEMA ws4_dev_private FROM PUBLIC, anon, authenticated, service_role;
-- USAGE permits RLS helpers; private tables and administrative helpers stay denied.
GRANT USAGE ON SCHEMA ws4_dev_private TO authenticated;
CREATE TABLE ws4_dev_private.installation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  contract_version text NOT NULL CHECK (contract_version = 'ws4-dev-core-1'),
  synthetic_only boolean NOT NULL DEFAULT true CHECK (synthetic_only),
  installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO ws4_dev_private.installation(contract_version) VALUES ('ws4-dev-core-1');

CREATE TABLE public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  id_number text UNIQUE, first_name text, surname text, email text UNIQUE,
  address text, phone_number text, phone text, date_of_birth date,
  profile_picture_url text, avatar_url text,
  user_type text NOT NULL DEFAULT 'patient' CHECK (user_type = 'patient'),
  role text NOT NULL DEFAULT 'patient'
    CHECK (role IN ('patient','dispatcher','dispatch_supervisor')),
  is_active boolean NOT NULL DEFAULT true,
  profile_complete boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- These are isolated synthetic scope fixtures, NOT canonical WS5 organisations.
CREATE TABLE ws4_dev_private.organisations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label text NOT NULL CHECK (label LIKE 'Synthetic %')
);
CREATE TABLE ws4_dev_private.memberships (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  role text NOT NULL CHECK (role IN ('dispatcher','dispatch_supervisor')),
  active boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, organisation_id)
);
-- Provisioned explicitly by the database owner for synthetic test identities.
-- No default catch-all route and no patient-controlled organisation selector.
CREATE TABLE ws4_dev_private.patient_routes (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(user_id),
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id)
);
CREATE TABLE public.incidents (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_progress','resolved','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(), last_viewed_at timestamptz,
  assigned_dispatcher_user_id uuid REFERENCES auth.users(id),
  accepted_at timestamptz,
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  CHECK ((assigned_dispatcher_user_id IS NULL) = (accepted_at IS NULL)),
  CHECK ((status IN ('pending','cancelled') AND assigned_dispatcher_user_id IS NULL)
      OR (status IN ('in_progress','resolved') AND assigned_dispatcher_user_id IS NOT NULL))
);
CREATE INDEX ws4_dev_incidents_scope ON public.incidents(organisation_id, status, id);
CREATE INDEX ws4_dev_incidents_patient ON public.incidents(user_id, id);
CREATE TABLE ws4_dev_private.incident_events (
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  version bigint NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('created','claimed','cancelled','resolved')),
  actor_user_id uuid REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  previous_status text, status text NOT NULL,
  PRIMARY KEY (incident_id, version)
);

CREATE FUNCTION ws4_dev_private.patient_active() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p
                 WHERE p.user_id=auth.uid() AND p.is_active IS TRUE);
$$;
CREATE FUNCTION ws4_dev_private.in_scope(p_organisation_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM ws4_dev_private.memberships m
    JOIN public.profiles p ON p.user_id=m.user_id
    WHERE m.user_id=auth.uid() AND m.organisation_id=p_organisation_id
      AND m.active IS TRUE AND p.is_active IS TRUE);
$$;
CREATE FUNCTION public.corvia_is_dispatch_operator() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM ws4_dev_private.memberships m
    JOIN public.profiles p ON p.user_id=m.user_id
    WHERE m.user_id=auth.uid() AND m.active IS TRUE AND p.is_active IS TRUE);
$$;
CREATE FUNCTION ws4_dev_private.patient_route() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_route uuid;
BEGIN
  SELECT r.organisation_id INTO v_route FROM ws4_dev_private.patient_routes r
  JOIN public.profiles p ON p.user_id=r.user_id
  WHERE r.user_id=auth.uid() AND p.is_active IS TRUE;
  IF v_route IS NULL THEN
    RAISE EXCEPTION 'Synthetic development routing has not been provisioned'
      USING ERRCODE='42501';
  END IF;
  RETURN v_route;
END $$;

-- INVOKER is intentional: callers cannot imitate the owner via a session flag.
CREATE FUNCTION ws4_dev_private.guard_profile() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_user <> 'postgres' THEN
    IF NEW.user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Profile ownership denied' USING ERRCODE='42501';
    END IF;
    IF TG_OP='INSERT' THEN
      IF NEW.role IS DISTINCT FROM 'patient' OR NEW.user_type IS DISTINCT FROM 'patient'
         OR NEW.is_active IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Patient registration only' USING ERRCODE='42501';
      END IF;
      NEW.created_at := now();
    ELSE
      IF (NEW.user_id,NEW.id,NEW.role,NEW.user_type,NEW.is_active,NEW.created_at)
         IS DISTINCT FROM
         (OLD.user_id,OLD.id,OLD.role,OLD.user_type,OLD.is_active,OLD.created_at) THEN
        RAISE EXCEPTION 'Profile authority fields are server controlled' USING ERRCODE='42501';
      END IF;
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_dev_profile_guard BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_profile();

CREATE FUNCTION ws4_dev_private.guard_incident() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_user <> 'postgres' THEN
    IF NEW.user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Incident ownership denied' USING ERRCODE='42501';
    END IF;
    IF TG_OP='INSERT' THEN
      IF NEW.status IS DISTINCT FROM 'pending' OR NEW.assigned_dispatcher_user_id IS NOT NULL
         OR NEW.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'New incidents must be unclaimed and pending' USING ERRCODE='42501';
      END IF;
      NEW.organisation_id := ws4_dev_private.patient_route();
      NEW.created_at := now();
      NEW.version := 1;
    ELSE
      IF OLD.status <> 'pending' OR OLD.assigned_dispatcher_user_id IS NOT NULL
         OR NEW.status <> 'cancelled' THEN
        RAISE EXCEPTION 'Only an unclaimed pending incident may be cancelled'
          USING ERRCODE='42501';
      END IF;
    END IF;
  END IF;
  IF TG_OP='UPDATE' THEN
    NEW.version := OLD.version + 1;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_dev_incident_guard BEFORE INSERT OR UPDATE ON public.incidents
FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_incident();

CREATE FUNCTION ws4_dev_private.record_incident_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO ws4_dev_private.incident_events
    (incident_id,version,event_type,actor_user_id,previous_status,status)
  VALUES (NEW.id,NEW.version,
    CASE WHEN TG_OP='INSERT' THEN 'created'
         WHEN NEW.status='in_progress' THEN 'claimed' ELSE NEW.status END,
    auth.uid(), CASE WHEN TG_OP='UPDATE' THEN OLD.status END, NEW.status);
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_dev_incident_event AFTER INSERT OR UPDATE ON public.incidents
FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.record_incident_event();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.installation ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.organisations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.patient_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.incident_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws4_dev_profile_read ON public.profiles FOR SELECT TO authenticated
USING (user_id=(SELECT auth.uid()));
CREATE POLICY ws4_dev_profile_insert ON public.profiles FOR INSERT TO authenticated
WITH CHECK (user_id=(SELECT auth.uid()));
CREATE POLICY ws4_dev_profile_update ON public.profiles FOR UPDATE TO authenticated
USING (user_id=(SELECT auth.uid())) WITH CHECK (user_id=(SELECT auth.uid()));
CREATE POLICY ws4_dev_incident_read ON public.incidents FOR SELECT TO authenticated
USING ((user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active()))
       OR ws4_dev_private.in_scope(organisation_id));
CREATE POLICY ws4_dev_incident_insert ON public.incidents FOR INSERT TO authenticated
WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active()));
CREATE POLICY ws4_dev_incident_cancel ON public.incidents FOR UPDATE TO authenticated
USING (user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active()))
WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT ws4_dev_private.patient_active()));

CREATE FUNCTION public.corvia_dispatch_access_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_memberships jsonb;
BEGIN
  IF NOT public.corvia_is_dispatch_operator() THEN
    RAISE EXCEPTION 'Active dispatch membership required' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('organisation_id',m.organisation_id,'role',m.role)
                  ORDER BY m.organisation_id) INTO v_memberships
  FROM ws4_dev_private.memberships m WHERE m.user_id=auth.uid() AND m.active IS TRUE;
  RETURN jsonb_build_object('user_id',auth.uid(),'memberships',v_memberships,
    'capabilities',jsonb_build_array('read_incidents','claim_incident'),
    'policy_version','ws4-dev-core-1','server_time',now());
END $$;

-- Exact legacy argument, response keys, lock, retry and error categories retained.
CREATE FUNCTION public.corvia_dispatch_accept_incident(p_incident_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_incident public.incidents%ROWTYPE;
BEGIN
  IF NOT public.corvia_is_dispatch_operator() THEN
    RAISE EXCEPTION 'Only an active dispatcher can accept emergencies.' USING ERRCODE='42501';
  END IF;
  -- Lock and recheck authority, including concurrent deactivation.
  PERFORM 1 FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispatch access revoked' USING ERRCODE='42501';
  END IF;
  SELECT i.* INTO v_incident FROM public.incidents i
  WHERE i.id=p_incident_id AND ws4_dev_private.in_scope(i.organisation_id) FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The emergency no longer exists within your scope.' USING ERRCODE='P0002';
  END IF;
  PERFORM 1 FROM ws4_dev_private.memberships
  WHERE user_id=auth.uid() AND organisation_id=v_incident.organisation_id AND active IS TRUE FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dispatch access revoked' USING ERRCODE='42501';
  END IF;
  IF NOT coalesce(v_incident.assigned_dispatcher_user_id=auth.uid()
                  AND v_incident.status='in_progress', false) THEN
    IF v_incident.status <> 'pending' OR v_incident.assigned_dispatcher_user_id IS NOT NULL THEN
      RAISE EXCEPTION 'This emergency has already been accepted or is no longer pending.' USING ERRCODE='P0001';
    END IF;
    UPDATE public.incidents SET status='in_progress', assigned_dispatcher_user_id=auth.uid(), accepted_at=now()
    WHERE id=p_incident_id RETURNING * INTO v_incident;
  END IF;
  RETURN jsonb_build_object('id',v_incident.id,'user_id',v_incident.user_id,
    'latitude',v_incident.latitude,'longitude',v_incident.longitude,
    'status',v_incident.status,'created_at',v_incident.created_at,
    'assigned_dispatcher_user_id',v_incident.assigned_dispatcher_user_id,'accepted_at',v_incident.accepted_at);
END $$;

-- Revoke explicit defaults as well as PUBLIC; hosting defaults vary by project.
REVOKE ALL ON ALL TABLES IN SCHEMA ws4_dev_private FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ws4_dev_private FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.profiles, public.incidents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.incidents_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.corvia_is_dispatch_operator(),
  public.corvia_dispatch_access_context(), public.corvia_dispatch_accept_incident(bigint)
FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT ON public.incidents TO authenticated;
GRANT INSERT(user_id,latitude,longitude,status) ON public.incidents TO authenticated;
GRANT UPDATE(status) ON public.incidents TO authenticated;
GRANT USAGE ON SEQUENCE public.incidents_id_seq TO authenticated;
GRANT EXECUTE ON FUNCTION ws4_dev_private.patient_active(), ws4_dev_private.in_scope(uuid),
  ws4_dev_private.patient_route(), public.corvia_is_dispatch_operator(),
  public.corvia_dispatch_access_context(), public.corvia_dispatch_accept_incident(bigint)
TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
