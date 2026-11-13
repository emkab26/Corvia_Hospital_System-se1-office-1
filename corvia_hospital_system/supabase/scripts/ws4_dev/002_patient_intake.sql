-- OWNED SYNTHETIC WS4 DEVELOPMENT ONLY. Additive delta after 001_secure_core.sql.
-- Not a shared Corvia migration. Review PATIENT_INTAKE.md before applying.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF current_user <> 'postgres' OR to_regclass('ws4_dev_private.installation') IS NULL THEN
    RAISE EXCEPTION 'Owned synthetic WS4 core and database owner required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ws4_dev_private.installation
                 WHERE singleton AND synthetic_only AND contract_version='ws4-dev-core-1') THEN
    RAISE EXCEPTION 'Owned synthetic WS4 core marker mismatch';
  END IF;
  IF to_regclass('ws4_dev_private.patient_intake_installation') IS NOT NULL
     OR to_regclass('ws4_dev_private.patient_intake_operations') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.incidents'::regclass
                 AND attname='location_source' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Patient intake delta already present or schema conflicts; inspect before repair';
  END IF;
END $$;

CREATE TABLE ws4_dev_private.patient_intake_installation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  contract_version text NOT NULL CHECK (contract_version='ws4-patient-intake-1'),
  synthetic_only boolean NOT NULL DEFAULT true CHECK (synthetic_only),
  installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO ws4_dev_private.patient_intake_installation(contract_version)
VALUES ('ws4-patient-intake-1');

ALTER TABLE public.incidents
  ALTER COLUMN latitude DROP NOT NULL,
  ALTER COLUMN longitude DROP NOT NULL,
  ADD COLUMN location_source text NOT NULL DEFAULT 'legacy',
  ADD COLUMN location_accuracy double precision,
  ADD COLUMN location_captured_at timestamptz,
  ADD COLUMN address text,
  ADD COLUMN details text,
  ADD CONSTRAINT ws4_intake_address_length CHECK (char_length(address)<=300),
  ADD CONSTRAINT ws4_intake_details_length CHECK (char_length(details)<=1000),
  ADD CONSTRAINT ws4_intake_location_shape CHECK (
    (location_source='legacy' AND latitude IS NOT NULL AND longitude IS NOT NULL
       AND location_accuracy IS NULL AND location_captured_at IS NULL)
    OR (location_source='gps' AND latitude IS NOT NULL AND longitude IS NOT NULL
       AND location_accuracy IS NOT NULL AND location_accuracy>=0
       AND location_accuracy<'Infinity'::double precision
       AND location_captured_at IS NOT NULL AND isfinite(location_captured_at))
    OR (location_source='manual' AND latitude IS NULL AND longitude IS NULL
       AND location_accuracy IS NULL AND location_captured_at IS NULL
       AND address IS NOT NULL AND btrim(address)<>'')
    OR (location_source='unavailable' AND latitude IS NULL AND longitude IS NULL
       AND location_accuracy IS NULL AND location_captured_at IS NULL)
  );

CREATE TABLE ws4_dev_private.patient_intake_operations (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  operation_id uuid NOT NULL,
  payload_sha256 bytea NOT NULL CHECK (octet_length(payload_sha256)=32),
  incident_id bigint NOT NULL UNIQUE REFERENCES public.incidents(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,operation_id)
);
ALTER TABLE ws4_dev_private.patient_intake_installation ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.patient_intake_operations ENABLE ROW LEVEL SECURITY;

-- Locks serialize deactivation/routing edits against request and recovery.
CREATE FUNCTION ws4_dev_private.patient_intake_scope() RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid(); v_scope uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Active patient access required' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.profiles WHERE user_id=v_actor AND role='patient'
    AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active patient access required' USING ERRCODE='42501';
  END IF;
  SELECT organisation_id INTO v_scope FROM ws4_dev_private.patient_routes
    WHERE user_id=v_actor FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient routing unavailable' USING ERRCODE='42501';
  END IF;
  RETURN v_scope;
END $$;

-- Internal projection only. IDs/versions are strings to preserve bigint on web.
CREATE FUNCTION ws4_dev_private.patient_intake_response(p_operation_id uuid,p_incident_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT jsonb_build_object(
    'operation_id',p_operation_id,'incident_id',i.id::text,'user_id',i.user_id,
    'status',i.status,'version',i.version::text,'created_at',i.created_at,
    'latitude',i.latitude,'longitude',i.longitude,'location_source',i.location_source,
    'location_accuracy',i.location_accuracy,'location_captured_at',i.location_captured_at,
    'address',i.address,'details',i.details)
  FROM public.incidents i WHERE i.id=p_incident_id;
$$;

CREATE FUNCTION public.corvia_patient_request_emergency(
  p_operation_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_location_accuracy double precision,
  p_location_captured_at timestamptz,
  p_address text,
  p_details text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' SET extra_float_digits=3 AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_scope uuid;
  v_address text := nullif(btrim(p_address),'');
  v_details text := nullif(btrim(p_details),'');
  v_source text;
  v_fingerprint bytea;
  v_prior ws4_dev_private.patient_intake_operations%ROWTYPE;
  v_incident public.incidents%ROWTYPE;
  v_now timestamptz;
BEGIN
  v_scope := ws4_dev_private.patient_intake_scope();
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR char_length(v_address)>300 OR char_length(v_details)>1000 THEN
    RAISE EXCEPTION 'Invalid emergency request' USING ERRCODE='22023';
  END IF;
  IF (p_latitude IS NULL) <> (p_longitude IS NULL) THEN
    RAISE EXCEPTION 'Location coordinates must be paired' USING ERRCODE='22023';
  END IF;
  IF p_latitude IS NULL THEN
    IF p_location_accuracy IS NOT NULL OR p_location_captured_at IS NOT NULL THEN
      RAISE EXCEPTION 'Location metadata requires coordinates' USING ERRCODE='22023';
    END IF;
    v_source := CASE WHEN v_address IS NULL THEN 'unavailable' ELSE 'manual' END;
  ELSE
    IF NOT (p_latitude BETWEEN -90 AND 90 AND p_longitude BETWEEN -180 AND 180)
       OR p_location_accuracy IS NULL
       OR NOT (p_location_accuracy>=0 AND p_location_accuracy<'Infinity'::double precision)
       OR p_location_captured_at IS NULL OR NOT isfinite(p_location_captured_at) THEN
      RAISE EXCEPTION 'Invalid location fix or metadata' USING ERRCODE='22023';
    END IF;
    v_source := 'gps';
  END IF;
  v_fingerprint := sha256(convert_to(jsonb_build_object(
    'latitude',p_latitude,'longitude',p_longitude,'location_accuracy',p_location_accuracy,
    'location_captured_at_epoch',extract(epoch FROM p_location_captured_at),
    'address',v_address,'details',v_details)::text,'UTF8'));

  -- Hash collisions serialize unrelated operations; they cannot mix identities.
  -- The actor+operation primary key remains the durable identity boundary.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::text||':'||p_operation_id::text,0));
  SELECT * INTO v_prior FROM ws4_dev_private.patient_intake_operations
    WHERE user_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_prior.payload_sha256<>v_fingerprint THEN
      RAISE EXCEPTION 'Operation identity already used with different request data' USING ERRCODE='22023';
    END IF;
    SELECT * INTO v_incident FROM public.incidents WHERE id=v_prior.incident_id;
    IF v_incident.user_id<>v_actor OR v_incident.organisation_id<>v_scope THEN
      RAISE EXCEPTION 'Patient request scope changed' USING ERRCODE='42501';
    END IF;
    -- An identical retry never refreshes GPS metadata or creates a second event.
    RETURN ws4_dev_private.patient_intake_response(p_operation_id,v_incident.id);
  END IF;

  v_now := clock_timestamp();
  IF v_source='gps' AND (p_location_captured_at<v_now-interval '120 seconds'
                        OR p_location_captured_at>v_now+interval '30 seconds') THEN
    RAISE EXCEPTION 'Location fix is stale or future dated' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.incidents(user_id,latitude,longitude,organisation_id,
    location_source,location_accuracy,location_captured_at,address,details)
  VALUES (v_actor,p_latitude,p_longitude,v_scope,
    v_source,p_location_accuracy,p_location_captured_at,v_address,v_details)
  RETURNING * INTO v_incident;
  INSERT INTO ws4_dev_private.patient_intake_operations(user_id,operation_id,payload_sha256,incident_id)
  VALUES (v_actor,p_operation_id,v_fingerprint,v_incident.id);
  RETURN ws4_dev_private.patient_intake_response(p_operation_id,v_incident.id);
END $$;

CREATE FUNCTION public.corvia_patient_request_status(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_actor uuid := auth.uid(); v_scope uuid; v_incident public.incidents%ROWTYPE;
BEGIN
  v_scope := ws4_dev_private.patient_intake_scope();
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'Operation identity required' USING ERRCODE='22023';
  END IF;
  -- If a request already holds this identity, recovery waits for its transaction
  -- before deciding whether a committed record exists.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::text||':'||p_operation_id::text,0));
  SELECT i.* INTO v_incident FROM ws4_dev_private.patient_intake_operations o
    JOIN public.incidents i ON i.id=o.incident_id
    WHERE o.user_id=v_actor AND o.operation_id=p_operation_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v_incident.user_id<>v_actor OR v_incident.organisation_id<>v_scope THEN
    RAISE EXCEPTION 'Patient request scope changed' USING ERRCODE='42501';
  END IF;
  RETURN ws4_dev_private.patient_intake_response(p_operation_id,v_incident.id);
END $$;

-- Advertise the additive projection only after its columns exist. The policy
-- identity/authority remain unchanged; old clients safely ignore the new token.
CREATE OR REPLACE FUNCTION public.corvia_dispatch_access_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_memberships jsonb;
BEGIN
  IF NOT public.corvia_is_dispatch_operator() THEN
    RAISE EXCEPTION 'Active dispatch membership required' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('organisation_id',m.organisation_id,'role',m.role)
                  ORDER BY m.organisation_id) INTO v_memberships
  FROM ws4_dev_private.memberships m WHERE m.user_id=auth.uid() AND m.active IS TRUE;
  RETURN jsonb_build_object('user_id',auth.uid(),'memberships',v_memberships,
    'capabilities',jsonb_build_array('read_incidents','claim_incident','read_intake_details'),
    'policy_version','ws4-dev-core-1','server_time',now());
END $$;

REVOKE ALL ON ws4_dev_private.patient_intake_installation,
  ws4_dev_private.patient_intake_operations FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION ws4_dev_private.patient_intake_scope(),
  ws4_dev_private.patient_intake_response(uuid,bigint),
  public.corvia_dispatch_access_context(),
  public.corvia_patient_request_emergency(uuid,double precision,double precision,double precision,timestamptz,text,text),
  public.corvia_patient_request_status(uuid) FROM PUBLIC,anon,authenticated,service_role;
-- Existing column-only incident INSERT/UPDATE grants stay unchanged. In
-- particular, clients cannot directly write the new intake fields or authority.
GRANT EXECUTE ON FUNCTION
  public.corvia_dispatch_access_context(),
  public.corvia_patient_request_emergency(uuid,double precision,double precision,double precision,timestamptz,text,text),
  public.corvia_patient_request_status(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
