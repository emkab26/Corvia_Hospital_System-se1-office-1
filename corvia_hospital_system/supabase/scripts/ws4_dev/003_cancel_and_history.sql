-- OWNED SYNTHETIC WS4 DEVELOPMENT ONLY. Additive after 001 and 002.
-- Review CANCEL_AND_HISTORY.md. This file does not install itself on any server.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_dev_private.installation') IS NULL
     OR to_regclass('ws4_dev_private.patient_intake_installation') IS NULL THEN
    RAISE EXCEPTION 'Owned synthetic WS4 core, intake and database owner required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ws4_dev_private.installation
                 WHERE singleton AND synthetic_only AND contract_version='ws4-dev-core-1')
     OR NOT EXISTS (SELECT 1 FROM ws4_dev_private.patient_intake_installation
                    WHERE singleton AND synthetic_only AND contract_version='ws4-patient-intake-1') THEN
    RAISE EXCEPTION 'Owned synthetic WS4 installation markers mismatch';
  END IF;
  IF to_regclass('ws4_dev_private.cancel_and_history_installation') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_attribute
                 WHERE attrelid='ws4_dev_private.patient_intake_operations'::regclass
                   AND attname='cancel_expected_version' AND NOT attisdropped)
     OR to_regprocedure('public.corvia_patient_cancel_emergency(uuid,bigint)') IS NOT NULL
     OR to_regprocedure('public.corvia_incident_history(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'Cancellation/history delta already present or schema conflicts; inspect before repair';
  END IF;
END $$;

CREATE TABLE ws4_dev_private.cancel_and_history_installation (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  contract_version text NOT NULL CHECK (contract_version='ws4-cancel-and-history-1'),
  synthetic_only boolean NOT NULL DEFAULT true CHECK (synthetic_only),
  installed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO ws4_dev_private.cancel_and_history_installation(contract_version)
VALUES ('ws4-cancel-and-history-1');
ALTER TABLE ws4_dev_private.cancel_and_history_installation ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.patient_intake_operations
  ADD COLUMN cancel_expected_version bigint CHECK (cancel_expected_version>0);

-- The existing intake identity can record one pending cancellation. Reuse the
-- exact identity lock shared by create/recovery, then lock the owned incident.
CREATE FUNCTION public.corvia_patient_cancel_emergency(p_operation_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_scope uuid;
  v_operation ws4_dev_private.patient_intake_operations%ROWTYPE;
  v_incident public.incidents%ROWTYPE;
BEGIN
  v_scope := ws4_dev_private.patient_intake_scope();
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR p_expected_version IS NULL OR p_expected_version<=0 THEN
    RAISE EXCEPTION 'Valid operation identity and expected version required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::text||':'||p_operation_id::text,0));
  SELECT * INTO v_operation FROM ws4_dev_private.patient_intake_operations
    WHERE user_id=v_actor AND operation_id=p_operation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient request unavailable within your scope' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_incident FROM public.incidents
    WHERE id=v_operation.incident_id AND user_id=v_actor AND organisation_id=v_scope FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient request unavailable within your scope' USING ERRCODE='42501';
  END IF;
  IF v_operation.cancel_expected_version IS NOT NULL THEN
    IF v_operation.cancel_expected_version<>p_expected_version THEN
      RAISE EXCEPTION 'Cancellation identity already used with another expected version' USING ERRCODE='22023';
    END IF;
    IF v_incident.status<>'cancelled' OR v_incident.assigned_dispatcher_user_id IS NOT NULL THEN
      RAISE EXCEPTION 'Recorded cancellation no longer matches current incident' USING ERRCODE='P0001';
    END IF;
    RETURN ws4_dev_private.patient_intake_response(p_operation_id,v_incident.id);
  END IF;
  IF v_incident.status<>'pending' OR v_incident.assigned_dispatcher_user_id IS NOT NULL
     OR v_incident.version<>p_expected_version THEN
    RAISE EXCEPTION 'Request changed or is no longer unclaimed and pending' USING ERRCODE='P0001';
  END IF;
  UPDATE ws4_dev_private.patient_intake_operations SET cancel_expected_version=p_expected_version
    WHERE user_id=v_actor AND operation_id=p_operation_id;
  -- Existing guard increments version; existing trigger records actor/time and
  -- the pending -> cancelled transition in this same transaction.
  UPDATE public.incidents SET status='cancelled' WHERE id=v_incident.id;
  RETURN ws4_dev_private.patient_intake_response(p_operation_id,v_incident.id);
END $$;

-- A bounded projection of durable audit rows, never an inferred timeline.
CREATE FUNCTION public.corvia_incident_history(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text;
  v_incident public.incidents%ROWTYPE;
  v_allowed boolean := false;
  v_events jsonb;
  v_count integer;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Active incident access required' USING ERRCODE='42501';
  END IF;
  SELECT role INTO v_role FROM public.profiles
    WHERE user_id=v_actor AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active incident access required' USING ERRCODE='42501';
  END IF;
  -- Filter visible authority before locking; an unrelated user must not take an
  -- incident lock. The applicable authority row is then locked/rechecked below.
  SELECT i.* INTO v_incident FROM public.incidents i WHERE i.id=p_incident_id
    AND ((i.user_id=v_actor AND v_role='patient' AND EXISTS (
      SELECT 1 FROM ws4_dev_private.patient_routes r
      WHERE r.user_id=v_actor AND r.organisation_id=i.organisation_id))
      OR ws4_dev_private.in_scope(i.organisation_id)) FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Incident history unavailable within your scope' USING ERRCODE='42501';
  END IF;
  IF v_incident.user_id=v_actor AND v_role='patient' THEN
    PERFORM 1 FROM ws4_dev_private.patient_routes
      WHERE user_id=v_actor AND organisation_id=v_incident.organisation_id FOR SHARE;
    v_allowed := FOUND;
  END IF;
  IF NOT v_allowed THEN
    PERFORM 1 FROM ws4_dev_private.memberships
      WHERE user_id=v_actor AND organisation_id=v_incident.organisation_id
        AND active IS TRUE FOR SHARE;
    v_allowed := FOUND;
  END IF;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Incident history unavailable within your scope' USING ERRCODE='42501';
  END IF;
  SELECT count(*),jsonb_agg(jsonb_build_object(
    'version',e.version::text,'event_type',e.event_type,'recorded_at',e.recorded_at,
    'status',e.status,'previous_status',e.previous_status) ORDER BY e.version)
    INTO v_count,v_events
  FROM (SELECT version,event_type,recorded_at,status,previous_status
        FROM ws4_dev_private.incident_events WHERE incident_id=p_incident_id
        ORDER BY version LIMIT 101) e;
  IF v_count=0 OR v_count>100 THEN
    RAISE EXCEPTION 'Incident history is empty or exceeds the supported event bound' USING ERRCODE='P0001';
  END IF;
  RETURN jsonb_build_object('incident_id',v_incident.id::text,'events',v_events);
END $$;

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
    'capabilities',jsonb_build_array('read_incidents','claim_incident','read_intake_details','read_incident_history'),
    'policy_version','ws4-dev-core-1','server_time',now());
END $$;

REVOKE ALL ON ws4_dev_private.cancel_and_history_installation
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.corvia_patient_cancel_emergency(uuid,bigint),
  public.corvia_incident_history(bigint),public.corvia_dispatch_access_context()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_patient_cancel_emergency(uuid,bigint),
  public.corvia_incident_history(bigint),public.corvia_dispatch_access_context() TO authenticated;
-- Preserve old column grants, private audit protection, 002 RPCs and claim RPC.
NOTIFY pgrst,'reload schema';
COMMIT;
