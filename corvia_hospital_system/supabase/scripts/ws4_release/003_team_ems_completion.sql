-- Additive completion safeguards for the reviewed WS4/team EMS bridge.
-- Install after 002_team_ems_handoff.sql, as the database owner.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_private.ems_handoff_links') IS NULL
     OR to_regprocedure('public.corvia_dispatch_command(bigint,uuid,bigint,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4/team EMS bridge must be installed by the database owner';
  END IF;
  IF to_regprocedure('public.corvia_ws4_close_incident(bigint,uuid,bigint,text,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'WS4 team completion is already installed; inspect before changing it';
  END IF;
END $$;

-- A provider demo cannot be added after a real team EMS incident is linked.
-- The incident row lock in corvia_dispatch_command serializes this with handoff.
CREATE FUNCTION ws4_private.guard_ems_provider() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links
             WHERE ws4_incident_id=NEW.incident_id) THEN
    IF TG_OP='INSERT' THEN
      IF NEW.provider_request_id IS NOT NULL
         OR NEW.provider_state IN ('accepted','unknown') THEN
        RAISE EXCEPTION 'Linked team EMS response cannot receive a separate provider request'
          USING ERRCODE='P0001';
      END IF;
    ELSIF (NEW.provider_request_id IS NOT NULL AND
           NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id)
          OR NEW.provider_state IN ('accepted','unknown') THEN
      RAISE EXCEPTION 'Linked team EMS response cannot receive a separate provider request'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_ems_provider_guard
BEFORE INSERT OR UPDATE OF provider_request_id, provider_state
ON ws4_private.incident_workspace FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_ems_provider();

-- Reuse the original versioned close command for every ordinary closure.
-- A team-confirmed cancellation needs its own terminal WS4 status and receipt.
CREATE FUNCTION public.corvia_ws4_close_incident(
  p_incident_id bigint, p_operation_id uuid, p_expected_version bigint,
  p_command text, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET TimeZone='UTC' AS $$
DECLARE v_role text; v_i public.incidents%ROWTYPE;
  v_old ws4_private.dispatch_commands%ROWTYPE; v_result jsonb;
  v_ems_status text; v_dispatch_state text; v_has_assignment boolean;
BEGIN
  IF p_command IS DISTINCT FROM 'close' THEN
    RAISE EXCEPTION 'Only closure is supported' USING ERRCODE='22023';
  END IF;
  v_role := ws4_private.lock_workspace(p_incident_id);
  SELECT e.status,e.dispatch_state INTO v_ems_status,v_dispatch_state
  FROM ws4_private.ems_handoff_links l
  JOIN public.corvia_ws6_incidents_actual e
    ON e.incident_id=l.ems_incident_id AND e.hospital_id=l.hospital_id
  WHERE l.ws4_incident_id=p_incident_id;
  IF NOT FOUND OR v_dispatch_state IS DISTINCT FROM 'cancelled' THEN
    RETURN public.corvia_dispatch_command(p_incident_id,p_operation_id,
      p_expected_version,p_command,p_payload);
  END IF;
  IF v_ems_status IS DISTINCT FROM 'Closed' THEN
    RAISE EXCEPTION 'Linked EMS cancellation is not confirmed closed'
      USING ERRCODE='P0001';
  END IF;
  IF auth.uid() IS NULL OR p_operation_id IS NULL
     OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR p_expected_version IS NULL OR p_expected_version<1
     OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
     OR NOT (p_payload ? 'text' AND (p_payload-'text'::text)='{}'::jsonb)
     OR jsonb_typeof(p_payload->'text')<>'string'
     OR char_length(p_payload->>'text')>1000
     OR btrim(p_payload->>'text')='' THEN
    RAISE EXCEPTION 'A bounded closure reason and operation are required'
      USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    auth.uid()::text||':command:'||p_operation_id::text,0));
  SELECT * INTO v_old FROM ws4_private.dispatch_commands
    WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (v_old.incident_id,v_old.expected_version,v_old.command,v_old.payload)
       IS DISTINCT FROM (p_incident_id,p_expected_version,p_command,p_payload) THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  IF v_i.version<>p_expected_version OR v_i.status<>'in_progress' THEN
    RAISE EXCEPTION 'Incident changed or closed' USING ERRCODE='P0001';
  END IF;
  IF v_role='patient' OR NOT (v_i.assigned_dispatcher_user_id=auth.uid()
                             OR v_role='dispatch_supervisor') THEN
    RAISE EXCEPTION 'Only the owner or scoped supervisor may close this request'
      USING ERRCODE='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM ws4_private.incident_workspace
             WHERE incident_id=p_incident_id
               AND provider_state IN ('accepted','unknown')) THEN
    RAISE EXCEPTION 'Finish or reconcile the provider response first'
      USING ERRCODE='P0001';
  END IF;
  IF to_regclass('public.incident_responder_assignments') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS(SELECT 1 FROM public.incident_responder_assignments WHERE incident_id=$1)'
      INTO v_has_assignment USING p_incident_id;
    IF v_has_assignment THEN
      RAISE EXCEPTION 'Fleet assignment requires completed handover or release'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  UPDATE public.incidents SET status='cancelled'
    WHERE id=p_incident_id RETURNING * INTO v_i;
  v_result := jsonb_build_object('incident_id',v_i.id::text,
    'operation_id',p_operation_id,'version',v_i.version::text,'command','close');
  INSERT INTO ws4_private.dispatch_commands
    (actor_id,operation_id,incident_id,expected_version,command,payload,result)
  VALUES(auth.uid(),p_operation_id,p_incident_id,p_expected_version,
    'close',p_payload,v_result);
  RETURN v_result;
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_close_incident(bigint,uuid,bigint,text,jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_close_incident(bigint,uuid,bigint,text,jsonb)
  TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
