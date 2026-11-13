-- Additive patient-safe projection. Owner review and install after 001-005.
-- It grants no patient access to Fleet, Paramedic, memberships or voice tables.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_private.ems_handoff_links') IS NULL
     OR to_regclass('public.corvia_ws6_incident_assignments_actual') IS NULL
     OR to_regclass('public.corvia_ws6_crews') IS NULL
     OR to_regclass('public.corvia_ws6_units_actual') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4 and team EMS contracts are required';
  END IF;
  IF to_regprocedure('public.corvia_ws4_patient_progress(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'Patient progress projection already exists; inspect before changing it';
  END IF;
END $$;

CREATE FUNCTION public.corvia_ws4_patient_progress(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_incident public.incidents%ROWTYPE;
  v_link ws4_private.ems_handoff_links%ROWTYPE;
  v_ems public.corvia_ws6_incidents_actual%ROWTYPE;
  v_latitude numeric;
  v_longitude numeric;
  v_location_at timestamptz;
  v_stage text;
BEGIN
  IF auth.uid() IS NULL OR NOT ws4_private.patient_active() THEN
    RAISE EXCEPTION 'Patient access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_incident FROM public.incidents
    WHERE id=p_incident_id AND user_id=auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Incident access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=v_incident.id;
  IF FOUND THEN
    SELECT * INTO v_ems FROM public.corvia_ws6_incidents_actual
      WHERE incident_id=v_link.ems_incident_id AND hospital_id=v_link.hospital_id;
  END IF;

  v_stage := CASE
    WHEN v_incident.status='cancelled' THEN 'cancelled'
    WHEN v_incident.status='resolved' THEN 'closed'
    WHEN v_incident.status='pending' THEN 'waiting_for_dispatch'
    WHEN v_link.ws4_incident_id IS NULL THEN 'dispatch_accepted'
    WHEN v_ems.dispatch_state='cancelled' THEN 'response_cancelled'
    WHEN v_ems.status IN ('At Hospital','Handed Over') THEN 'at_hospital'
    WHEN v_ems.status='Transporting' THEN 'transporting'
    WHEN v_ems.status='On Scene' THEN 'on_scene'
    WHEN v_ems.status='En Route' THEN 'en_route'
    WHEN v_ems.dispatch_state='escalated' THEN 'response_review'
    WHEN v_ems.dispatch_state='assigned' THEN 'unit_assigned'
    ELSE 'dispatch_accepted'
  END;

  IF v_incident.status='in_progress' AND v_link.ws4_incident_id IS NOT NULL
     AND v_ems.dispatch_state IS DISTINCT FROM 'cancelled' THEN
    SELECT u.latitude,u.longitude,u.location_updated_at
      INTO v_latitude,v_longitude,v_location_at
      FROM public.corvia_ws6_incident_assignments_actual a
      JOIN public.corvia_ws6_crews c ON c.crew_id=a.crew_id
        AND c.hospital_id=a.hospital_id
      JOIN public.corvia_ws6_units_actual u ON u.unit_id=c.unit_id
        AND u.hospital_id=c.hospital_id AND u.is_active
      WHERE a.hospital_id=v_link.hospital_id
        AND a.incident_id=v_link.ems_incident_id AND a.is_active
      ORDER BY a.assigned_datetime DESC, a.assignment_id DESC LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'incident_id',v_incident.id::text,
    'stage',v_stage,
    'observed_at',now(),
    'unit_latitude',CASE WHEN v_location_at >= now()-interval '5 minutes'
      THEN v_latitude ELSE NULL END,
    'unit_longitude',CASE WHEN v_location_at >= now()-interval '5 minutes'
      THEN v_longitude ELSE NULL END,
    'location_at',CASE WHEN v_location_at >= now()-interval '5 minutes'
      THEN v_location_at ELSE NULL END
  );
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_patient_progress(bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_patient_progress(bigint)
  TO authenticated;
COMMIT;
