-- Candidate migration for an explicit patient callback number. Review the
-- installed 001 function definitions before applying; never run without backup.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF to_regclass('ws4_private.patient_intake_operations') IS NULL
     OR to_regprocedure('public.corvia_patient_request_emergency(uuid,double precision,double precision,double precision,timestamptz,text,text)') IS NULL
     OR to_regprocedure('ws4_private.patient_intake_response(uuid,bigint)') IS NULL
     OR to_regprocedure('ws4_private.lock_workspace(bigint)') IS NULL THEN
    RAISE EXCEPTION 'WS4 intake and workspace must be installed first';
  END IF;
  IF to_regclass('ws4_private.patient_callbacks') IS NOT NULL
     OR to_regprocedure('public.corvia_ws4_callback_number(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'Callback contract already exists; inspect before changing it';
  END IF;
END $$;

CREATE TABLE ws4_private.patient_callbacks (
  incident_id bigint PRIMARY KEY REFERENCES public.incidents(id),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  callback_number text,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ws4_callback_shape CHECK (
    callback_number IS NULL OR callback_number ~ '^\+?[0-9]{7,15}$')
);
ALTER TABLE ws4_private.patient_callbacks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.patient_callbacks FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the established response shape and add one nullable field.
CREATE OR REPLACE FUNCTION ws4_private.patient_intake_response(
  p_operation_id uuid,p_incident_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT jsonb_build_object(
    'operation_id',p_operation_id,'incident_id',i.id::text,'user_id',i.user_id,
    'status',i.status,'version',i.version::text,'created_at',i.created_at,
    'latitude',i.latitude,'longitude',i.longitude,'location_source',i.location_source,
    'location_accuracy',i.location_accuracy,'location_captured_at',i.location_captured_at,
    'address',i.address,'details',i.details,'callback_number',c.callback_number)
  FROM public.incidents i LEFT JOIN ws4_private.patient_callbacks c
    ON c.incident_id=i.id AND c.user_id=i.user_id
  WHERE i.id=p_incident_id;
$$;

-- The existing seven-argument RPC remains for older app builds. The new
-- overload calls it in the same transaction; a callback failure rolls back
-- incident creation, and a retry cannot change the callback for an operation.
CREATE FUNCTION public.corvia_patient_request_emergency(
  p_operation_id uuid,p_latitude double precision,p_longitude double precision,
  p_location_accuracy double precision,p_location_captured_at timestamptz,
  p_address text,p_details text,p_callback_number text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_callback text := nullif(btrim(p_callback_number),'');
  v_response jsonb; v_incident_id bigint;
BEGIN
  IF v_callback IS NOT NULL THEN
    IF char_length(v_callback)>40 OR v_callback !~ '^[+0-9 ()-]+$' THEN
      RAISE EXCEPTION 'Invalid callback number' USING ERRCODE='22023';
    END IF;
    v_callback := regexp_replace(v_callback,'[^+0-9]','','g');
    IF v_callback !~ '^\+?[0-9]{7,15}$' THEN
      RAISE EXCEPTION 'Invalid callback number' USING ERRCODE='22023';
    END IF;
  END IF;
  v_response := public.corvia_patient_request_emergency(
    p_operation_id,p_latitude,p_longitude,p_location_accuracy,
    p_location_captured_at,p_address,p_details);
  v_incident_id := (v_response->>'incident_id')::bigint;
  INSERT INTO ws4_private.patient_callbacks(incident_id,user_id,callback_number)
    VALUES (v_incident_id,auth.uid(),v_callback)
    ON CONFLICT (incident_id) DO NOTHING;
  IF (SELECT c.user_id=auth.uid() AND
             c.callback_number IS NOT DISTINCT FROM v_callback
      FROM ws4_private.patient_callbacks c WHERE c.incident_id=v_incident_id)
      IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Callback differs from the original request'
      USING ERRCODE='22023';
  END IF;
  RETURN ws4_private.patient_intake_response(p_operation_id,v_incident_id);
END $$;

-- Return the explicit number only to the current claimed dispatcher or an
-- active supervisor in scope. An unclaimed queue never exposes contact data.
CREATE FUNCTION public.corvia_ws4_callback_number(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text; v_incident public.incidents%ROWTYPE; v_callback text;
BEGIN
  v_role := ws4_private.lock_workspace(p_incident_id);
  SELECT * INTO v_incident FROM public.incidents WHERE id=p_incident_id;
  IF v_role<>'dispatch_supervisor' AND
     (v_role<>'dispatcher' OR
      v_incident.assigned_dispatcher_user_id IS DISTINCT FROM auth.uid()) THEN
    RAISE EXCEPTION 'Callback access denied' USING ERRCODE='42501';
  END IF;
  SELECT callback_number INTO v_callback FROM ws4_private.patient_callbacks
    WHERE incident_id=p_incident_id AND user_id=v_incident.user_id;
  RETURN jsonb_build_object('incident_id',p_incident_id::text,
    'callback_number',v_callback);
END $$;

REVOKE ALL ON FUNCTION
  public.corvia_patient_request_emergency(uuid,double precision,double precision,double precision,timestamptz,text,text,text),
  public.corvia_ws4_callback_number(bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.corvia_patient_request_emergency(uuid,double precision,double precision,double precision,timestamptz,text,text,text),
  public.corvia_ws4_callback_number(bigint)
  TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
