-- WS4 to the team's Fleet/Paramedic workspace. Owner-reviewed additive install.
-- Run only after 001_shared_upgrade.sql and workstreams/11 + 13.
-- No route, account, incident or resource is provisioned by this script.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_private.response_assignments') IS NULL
     OR to_regclass('public.corvia_ws6_incidents_actual') IS NULL
     OR to_regclass('public.corvia_ops_memberships') IS NULL
     OR to_regprocedure('public.corvia_ems_command(uuid,uuid,uuid,text,jsonb)') IS NULL
     OR to_regprocedure('public.corvia_ops_role(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4 and team EMS contracts must be installed by the database owner';
  END IF;
  IF to_regclass('ws4_private.ems_handoff_routes') IS NOT NULL THEN
    RAISE EXCEPTION 'WS4 EMS handoff is already installed; inspect before changing it';
  END IF;
END $$;

CREATE TABLE ws4_private.ems_handoff_routes (
  organisation_id uuid PRIMARY KEY REFERENCES ws4_private.organisations(id),
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  active boolean NOT NULL DEFAULT false,
  reviewed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ws4_private.ems_handoff_links (
  ws4_incident_id bigint PRIMARY KEY REFERENCES public.incidents(id),
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  ems_incident_id bigint NOT NULL UNIQUE REFERENCES public.corvia_ws6_incidents_actual(incident_id),
  operation_id uuid NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  priority text NOT NULL CHECK(priority IN ('Critical','High','Medium','Low')),
  required_capability text NOT NULL CHECK(required_capability IN ('BLS','ILS','ALS')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(created_by,operation_id)
);

ALTER TABLE ws4_private.ems_handoff_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_handoff_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.ems_handoff_routes, ws4_private.ems_handoff_links
  FROM PUBLIC, anon, authenticated, service_role;

-- A reviewed team route makes team Fleet the sole allocation authority for the
-- organisation. Route activation cannot strand an existing active WS4 offer.
CREATE FUNCTION ws4_private.guard_ems_route() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'ws4_ems_route:'||NEW.organisation_id::text,0));
  IF TG_OP='UPDATE' AND (NEW.active IS DISTINCT FROM OLD.active
      OR NEW.hospital_id IS DISTINCT FROM OLD.hospital_id) AND EXISTS (
    SELECT 1 FROM ws4_private.ems_handoff_links l
    JOIN public.incidents i ON i.id=l.ws4_incident_id
    WHERE i.organisation_id=NEW.organisation_id
  ) THEN
    RAISE EXCEPTION 'Reviewed EMS route cannot change while linked incidents exist'
      USING ERRCODE='P0001';
  END IF;
  IF NEW.active AND EXISTS (
    SELECT 1 FROM ws4_private.response_assignments a
    JOIN public.incidents i ON i.id=a.incident_id
    WHERE i.organisation_id=NEW.organisation_id AND a.active
  ) THEN
    RAISE EXCEPTION 'Release active WS4 response assignments before enabling team EMS routing'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_ems_route_guard BEFORE INSERT OR UPDATE OF active, hospital_id
ON ws4_private.ems_handoff_routes FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_ems_route();

CREATE FUNCTION ws4_private.block_parallel_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_organisation uuid;
BEGIN
  SELECT organisation_id INTO v_organisation FROM public.incidents
    WHERE id=NEW.incident_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'ws4_ems_route:'||v_organisation::text,0));
  IF NEW.active AND EXISTS (
    SELECT 1 FROM public.incidents i
    JOIN ws4_private.ems_handoff_routes r ON r.organisation_id=i.organisation_id
    WHERE i.id=NEW.incident_id AND r.active
  ) THEN
    RAISE EXCEPTION 'Team EMS routing is active; assign through Fleet/Paramedic workspace'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_ems_assignment_guard BEFORE INSERT OR UPDATE OF active
ON ws4_private.response_assignments FOR EACH ROW
EXECUTE FUNCTION ws4_private.block_parallel_assignment();

-- A WS4 close cannot claim completion before the linked team incident closes.
CREATE FUNCTION ws4_private.guard_ems_closure() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_status text; v_dispatch_state text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('resolved','cancelled')
     AND EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links
                 WHERE ws4_incident_id=NEW.id) THEN
    SELECT e.status,e.dispatch_state INTO v_status,v_dispatch_state
    FROM ws4_private.ems_handoff_links l
    JOIN public.corvia_ws6_incidents_actual e ON e.incident_id=l.ems_incident_id
      AND e.hospital_id=l.hospital_id
    WHERE l.ws4_incident_id=NEW.id;
    IF v_status IS DISTINCT FROM 'Closed'
       OR (NEW.status='resolved' AND v_dispatch_state IS DISTINCT FROM 'closed')
       OR (NEW.status='cancelled' AND v_dispatch_state IS DISTINCT FROM 'cancelled') THEN
      RAISE EXCEPTION 'Linked EMS incident must reach the matching closed state before WS4 closure'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_ems_closure_guard BEFORE UPDATE OF status
ON public.incidents FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_ems_closure();

-- Read only operational linkage; do not return crew clinical records or patient
-- identity. Both WS4 scope and team hospital membership are checked on each read.
CREATE FUNCTION public.corvia_ws4_ems_handoff_status(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_i public.incidents%ROWTYPE; v_route ws4_private.ems_handoff_routes%ROWTYPE;
  v_link ws4_private.ems_handoff_links%ROWTYPE; v_team_role text; v_ems record;
BEGIN
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  IF NOT FOUND OR NOT ws4_private.in_scope(v_i.organisation_id) THEN
    RAISE EXCEPTION 'Dispatch access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_route FROM ws4_private.ems_handoff_routes
    WHERE organisation_id=v_i.organisation_id AND active;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('mode','unconfigured','linked',false,'can_handoff',false);
  END IF;
  v_team_role := public.corvia_ops_role(v_route.hospital_id);
  IF v_team_role IS NULL THEN
    RETURN jsonb_build_object('mode','team','linked',false,'can_handoff',false,
      'team_access',false,'hospital_id',v_route.hospital_id);
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_incident_id;
  IF FOUND THEN
    SELECT incident_number,status,dispatch_state INTO v_ems
    FROM public.corvia_ws6_incidents_actual
    WHERE incident_id=v_link.ems_incident_id AND hospital_id=v_link.hospital_id;
    RETURN jsonb_build_object('mode','team','linked',true,'team_access',true,
      'hospital_id',v_link.hospital_id,'ems_incident_id',v_link.ems_incident_id::text,
      'ems_number',v_ems.incident_number,'ems_status',v_ems.status,
      'dispatch_state',v_ems.dispatch_state);
  END IF;
  RETURN jsonb_build_object('mode','team','linked',false,'team_access',true,
    'hospital_id',v_route.hospital_id,
    'can_handoff',v_i.status='in_progress'
       AND v_i.assigned_dispatcher_user_id=auth.uid()
       AND NOT EXISTS(SELECT 1 FROM ws4_private.response_assignments
                      WHERE incident_id=v_i.id)
       AND NOT EXISTS(SELECT 1 FROM ws4_private.incident_workspace
                      WHERE incident_id=v_i.id AND provider_state IN ('accepted','unknown')));
END $$;

-- The team command inserts the EMS incident and its receipt inside this same
-- transaction. A retry returns the durable link; it never creates a second case.
CREATE FUNCTION public.corvia_ws4_handoff_to_ems(
  p_incident_id bigint, p_hospital_id uuid, p_session uuid,
  p_operation_id uuid, p_priority text, p_required_capability text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_i public.incidents%ROWTYPE; v_route ws4_private.ems_handoff_routes%ROWTYPE;
  v_link ws4_private.ems_handoff_links%ROWTYPE; v_result jsonb; v_ems_id bigint;
BEGIN
  IF auth.uid() IS NULL OR p_operation_id IS NULL OR p_session IS NULL
     OR p_priority IS NULL OR p_priority NOT IN ('Critical','High','Medium','Low')
     OR p_required_capability IS NULL
     OR p_required_capability NOT IN ('BLS','ILS','ALS') THEN
    RAISE EXCEPTION 'Valid handoff identity, priority and capability are required'
      USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id FOR UPDATE;
  IF NOT FOUND OR NOT ws4_private.in_scope(v_i.organisation_id) THEN
    RAISE EXCEPTION 'Dispatch access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_route FROM ws4_private.ems_handoff_routes
    WHERE organisation_id=v_i.organisation_id AND hospital_id=p_hospital_id AND active FOR SHARE;
  IF NOT FOUND OR public.corvia_ops_role(p_hospital_id) IS NULL THEN
    RAISE EXCEPTION 'Reviewed team route and current EMS membership required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=v_i.id;
  IF FOUND THEN
    IF v_link.created_by<>auth.uid() OR v_link.operation_id<>p_operation_id
       OR v_link.hospital_id<>p_hospital_id OR v_link.priority<>p_priority
       OR v_link.required_capability<>p_required_capability THEN
      RAISE EXCEPTION 'Incident is already linked; refresh its EMS status'
        USING ERRCODE='P0001';
    END IF;
    RETURN public.corvia_ws4_ems_handoff_status(v_i.id);
  END IF;
  IF v_i.status<>'in_progress' OR v_i.assigned_dispatcher_user_id<>auth.uid()
     OR EXISTS(SELECT 1 FROM ws4_private.response_assignments WHERE incident_id=v_i.id)
     OR EXISTS(SELECT 1 FROM ws4_private.incident_workspace
               WHERE incident_id=v_i.id AND provider_state IN ('accepted','unknown')) THEN
    RAISE EXCEPTION 'Claimed incident without an existing response/provider commitment required'
      USING ERRCODE='P0001';
  END IF;
  v_result := public.corvia_ems_command(p_hospital_id,p_session,p_operation_id,
    'incident',jsonb_strip_nulls(jsonb_build_object('priority',p_priority,
      'required_capability',p_required_capability,
      'incident_type','Medical Emergency',
      'dispatch_notes',nullif(btrim(left(v_i.details,2000)),''),
      'scene_address',nullif(btrim(v_i.address),''),'latitude',v_i.latitude,
      'longitude',v_i.longitude)));
  v_ems_id := (v_result->>'id')::bigint;
  IF v_ems_id IS NULL THEN
    RAISE EXCEPTION 'EMS incident creation was not confirmed' USING ERRCODE='P0001';
  END IF;
  INSERT INTO ws4_private.ems_handoff_links(ws4_incident_id,hospital_id,
    ems_incident_id,operation_id,created_by,priority,required_capability)
  VALUES(v_i.id,p_hospital_id,v_ems_id,p_operation_id,auth.uid(),
    p_priority,p_required_capability);
  RETURN public.corvia_ws4_ems_handoff_status(v_i.id);
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_ems_handoff_status(bigint),
  public.corvia_ws4_handoff_to_ems(bigint,uuid,uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_ems_handoff_status(bigint),
  public.corvia_ws4_handoff_to_ems(bigint,uuid,uuid,uuid,text,text)
  TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
