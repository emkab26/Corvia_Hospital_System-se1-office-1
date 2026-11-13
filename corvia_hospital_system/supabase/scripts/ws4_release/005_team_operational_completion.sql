-- WS4 linked team completion. Owner review/install after 004; no team SQL is replaced.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$ BEGIN
  IF current_user<>'postgres' OR to_regclass('ws4_private.ems_backups') IS NULL
     OR to_regclass('public.corvia_ops_messages') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4/team scripts through 004 are required';
  END IF;
  IF to_regclass('ws4_private.ems_team_exceptions') IS NOT NULL THEN
    RAISE EXCEPTION 'WS4 operational completion already installed';
  END IF;
END $$;

ALTER TABLE ws4_private.ems_backups ADD COLUMN acknowledgement_due_at timestamptz;
UPDATE ws4_private.ems_backups SET acknowledgement_due_at=offered_at+interval '2 minutes';
ALTER TABLE ws4_private.ems_backups ALTER COLUMN acknowledgement_due_at SET NOT NULL;
CREATE TABLE ws4_private.ems_team_exceptions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  ems_incident_id bigint NOT NULL REFERENCES public.corvia_ws6_incidents_actual(incident_id),
  kind text NOT NULL CHECK(kind IN ('no_patient','unsafe_scene','refusal','unit_failure',
    'backup_required','no_resource','multiple_patients','handover_failed')),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 1000),
  recorded_by uuid NOT NULL REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  destination_at_record bigint,
  active boolean NOT NULL DEFAULT true,
  resolved_by uuid REFERENCES auth.users(id),
  resolved_at timestamptz,
  resolution text,
  CHECK ((active AND resolved_by IS NULL AND resolved_at IS NULL AND resolution IS NULL)
    OR (NOT active AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL
      AND length(btrim(resolution))>=5))
);
CREATE UNIQUE INDEX ems_one_active_team_exception
  ON ws4_private.ems_team_exceptions(ems_incident_id,kind) WHERE active;
CREATE TABLE ws4_private.ems_team_destinations (
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  ems_incident_id bigint PRIMARY KEY REFERENCES public.corvia_ws6_incidents_actual(incident_id),
  facility_id bigint NOT NULL REFERENCES public.corvia_ws6_receiving_facilities(facility_id),
  chosen_by uuid NOT NULL REFERENCES auth.users(id),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 1000),
  selected_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 1
);
CREATE TABLE ws4_private.ems_team_receipts (
  actor uuid NOT NULL REFERENCES auth.users(id), operation_id uuid NOT NULL,
  action text NOT NULL, payload jsonb NOT NULL, result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor,operation_id)
);
CREATE TABLE ws4_private.ems_team_deadline_alerts (
  kind text NOT NULL CHECK(kind IN ('primary','backup')),
  resource_id bigint NOT NULL, hospital_id uuid NOT NULL,
  ems_incident_id bigint NOT NULL, alerted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(kind,resource_id)
);
ALTER TABLE ws4_private.ems_team_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_team_destinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_team_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_team_deadline_alerts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.ems_team_exceptions,ws4_private.ems_team_destinations,
  ws4_private.ems_team_receipts,ws4_private.ems_team_deadline_alerts
  FROM PUBLIC,anon,authenticated,service_role;

-- Existing team exception commands are captured atomically for linked cases.
CREATE FUNCTION ws4_private.capture_team_exception() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_kind text;
BEGIN
  v_kind:=NEW.new_value->>'exception';
  IF NEW.action_type='exception' AND v_kind IN
     ('no_patient','unsafe_scene','refusal','unit_failure','backup_required')
     AND EXISTS(SELECT 1 FROM ws4_private.ems_handoff_links l
       WHERE l.hospital_id=NEW.hospital_id AND l.ems_incident_id=NEW.incident_id) THEN
    INSERT INTO ws4_private.ems_team_exceptions
      (hospital_id,ems_incident_id,kind,reason,recorded_by,destination_at_record)
    VALUES(NEW.hospital_id,NEW.incident_id,v_kind,NEW.reason,NEW.actor_auth_user_id,
      (SELECT d.facility_id FROM ws4_private.ems_team_destinations d
       WHERE d.ems_incident_id=NEW.incident_id));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_capture_team_exception AFTER INSERT ON public.corvia_ws6_audit_logs
FOR EACH ROW EXECUTE FUNCTION ws4_private.capture_team_exception();

CREATE FUNCTION ws4_private.guard_linked_team_progress() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NOT EXISTS
    (SELECT 1 FROM ws4_private.ems_handoff_links l
     WHERE l.hospital_id=NEW.hospital_id AND l.ems_incident_id=NEW.incident_id) THEN
    RETURN NEW;
  END IF;
  IF NEW.status='Accepted' AND OLD.status='Dispatched'
     AND OLD.acknowledgement_due_at IS NOT NULL
     AND OLD.acknowledgement_due_at<=now() THEN
    RAISE EXCEPTION 'Primary crew acknowledgement overdue; dispatch must review'
      USING ERRCODE='P0001';
  END IF;
  IF NEW.status IN ('Transporting','At Hospital','Handed Over','Closed') THEN
    IF EXISTS(SELECT 1 FROM ws4_private.ems_team_exceptions x
      WHERE x.ems_incident_id=NEW.incident_id AND x.active) THEN
      RAISE EXCEPTION 'Resolve linked safety exceptions before progression'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  IF NEW.status='Transporting' THEN
    IF NOT EXISTS(SELECT 1 FROM public.corvia_ws6_incident_patients p
       WHERE p.hospital_id=NEW.hospital_id AND p.incident_id=NEW.incident_id
         AND p.is_active) OR EXISTS(SELECT 1 FROM public.corvia_ws6_incident_patients p
       WHERE p.hospital_id=NEW.hospital_id AND p.incident_id=NEW.incident_id
         AND p.is_active AND (p.confirmation_status<>'Confirmed'
           OR p.confirmed_at IS NULL)) THEN
      RAISE EXCEPTION 'Confirm every assigned patient before transport'
        USING ERRCODE='P0001';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM ws4_private.ems_team_destinations d
      JOIN public.corvia_ws6_receiving_facilities f
        ON f.facility_id=d.facility_id AND f.hospital_id=d.hospital_id AND f.is_active
      WHERE d.ems_incident_id=NEW.incident_id AND d.hospital_id=NEW.hospital_id) THEN
      RAISE EXCEPTION 'Select an active receiving destination before transport'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_guard_linked_team_progress BEFORE UPDATE OF status
ON public.corvia_ws6_incidents_actual FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_linked_team_progress();

CREATE FUNCTION ws4_private.guard_linked_handover_destination() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM ws4_private.ems_handoff_links l
    WHERE l.hospital_id=NEW.hospital_id AND l.ems_incident_id=NEW.incident_id)
    AND NOT EXISTS(SELECT 1 FROM ws4_private.ems_team_destinations d
      JOIN public.corvia_ws6_receiving_facilities f
        ON f.facility_id=d.facility_id AND f.hospital_id=d.hospital_id AND f.is_active
      WHERE d.hospital_id=NEW.hospital_id AND d.ems_incident_id=NEW.incident_id
        AND d.facility_id=NEW.facility_id) THEN
    RAISE EXCEPTION 'Handover must match the active reviewed destination'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_guard_linked_handover BEFORE INSERT ON public.corvia_ws6_handovers
FOR EACH ROW EXECUTE FUNCTION ws4_private.guard_linked_handover_destination();

CREATE FUNCTION ws4_private.expire_released_primary_readiness() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF OLD.is_active AND NOT NEW.is_active AND EXISTS
    (SELECT 1 FROM ws4_private.ems_handoff_links l WHERE l.hospital_id=NEW.hospital_id
      AND l.ems_incident_id=NEW.incident_id) THEN
    UPDATE public.corvia_ops_readiness SET expires_at=least(expires_at,now())
    WHERE hospital_id=NEW.hospital_id AND unit_id=(SELECT c.unit_id
      FROM public.corvia_ws6_crews c WHERE c.crew_id=NEW.crew_id
        AND c.hospital_id=NEW.hospital_id);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_expire_linked_primary_readiness
AFTER UPDATE OF is_active ON public.corvia_ws6_incident_assignments_actual
FOR EACH ROW EXECUTE FUNCTION ws4_private.expire_released_primary_readiness();

CREATE FUNCTION ws4_private.guard_backup_offer_deadline() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    NEW.acknowledgement_due_at:=NEW.offered_at+interval '2 minutes';
  ELSIF OLD.state='offered' AND NEW.state='acknowledged'
    AND OLD.acknowledgement_due_at<=now() THEN
    RAISE EXCEPTION 'Backup offer overdue; dispatch must review'
      USING ERRCODE='P0001';
  ELSIF TG_OP='UPDATE' AND OLD.state='offered' AND NEW.state='acknowledged'
    AND (NOT EXISTS(SELECT 1 FROM public.corvia_ws6_units_actual u
      WHERE u.hospital_id=OLD.hospital_id AND u.unit_id=OLD.unit_id
        AND u.is_active AND u.status='Assigned'
        AND u.readiness_status NOT IN ('maintenance','off_duty')
        AND u.compliance_expiry_date >= (now() AT TIME ZONE 'Africa/Johannesburg')::date)
      OR NOT EXISTS(SELECT 1 FROM public.corvia_ops_readiness r
        WHERE r.hospital_id=OLD.hospital_id AND r.unit_id=OLD.unit_id
          AND r.expires_at>now() AND r.vehicle_ok AND r.equipment_ok
          AND r.oxygen_ok AND r.fuel_ok AND r.communications_ok AND r.cleaning_ok)
      OR EXISTS(SELECT 1 FROM public.corvia_ops_faults f
        WHERE f.hospital_id=OLD.hospital_id AND f.unit_id=OLD.unit_id
          AND f.resolved_at IS NULL)) THEN
    RAISE EXCEPTION 'Backup vehicle readiness changed; dispatch must review'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_backup_offer_deadline BEFORE INSERT OR UPDATE OF state
ON ws4_private.ems_backups FOR EACH ROW EXECUTE FUNCTION ws4_private.guard_backup_offer_deadline();

CREATE TABLE ws4_private.ems_failed_handovers (
  handover_id bigint PRIMARY KEY REFERENCES public.corvia_ws6_handovers(handover_id),
  exception_id bigint NOT NULL REFERENCES ws4_private.ems_team_exceptions(id),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ws4_private.ems_failed_handovers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.ems_failed_handovers FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION ws4_private.guard_receiver_destination() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.acknowledged AND NOT OLD.acknowledged AND EXISTS
    (SELECT 1 FROM ws4_private.ems_handoff_links l
     WHERE l.hospital_id=NEW.hospital_id AND l.ems_incident_id=NEW.incident_id)
    AND (EXISTS(SELECT 1 FROM ws4_private.ems_failed_handovers fh
      WHERE fh.handover_id=NEW.handover_id) OR NOT EXISTS
      (SELECT 1 FROM ws4_private.ems_team_destinations d
       WHERE d.hospital_id=NEW.hospital_id AND d.ems_incident_id=NEW.incident_id
         AND d.facility_id=NEW.facility_id)) THEN
    RAISE EXCEPTION 'Receiving confirmation must match the current destination'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_receiver_destination_guard BEFORE UPDATE OF acknowledged
ON public.corvia_ws6_handovers FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_receiver_destination();

CREATE FUNCTION ws4_private.guard_all_linked_handovers() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('Handed Over','Closed')
     AND EXISTS(SELECT 1 FROM ws4_private.ems_handoff_links l
       WHERE l.hospital_id=NEW.hospital_id AND l.ems_incident_id=NEW.incident_id)
     AND NEW.dispatch_state<>'cancelled' AND EXISTS
       (SELECT 1 FROM public.corvia_ws6_handovers ho
        WHERE ho.hospital_id=NEW.hospital_id AND ho.incident_id=NEW.incident_id
          AND NOT ho.acknowledged AND NOT EXISTS
            (SELECT 1 FROM ws4_private.ems_failed_handovers fh
             WHERE fh.handover_id=ho.handover_id)) THEN
    RAISE EXCEPTION 'Resolve every pending receiving handover before completion'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_all_linked_handovers_guard BEFORE UPDATE OF status
ON public.corvia_ws6_incidents_actual FOR EACH ROW
EXECUTE FUNCTION ws4_private.guard_all_linked_handovers();

-- Resolves the current signed-in role against the linked incident. Backup
-- membership grants the backup communication surface, never clinical commands.
CREATE FUNCTION ws4_private.linked_actor(p_ws4 bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_link ws4_private.ems_handoff_links%ROWTYPE;
  v_i public.incidents%ROWTYPE; v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_ws4;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_ws4;
  v_role:=public.corvia_ops_role(v_link.hospital_id);
  IF ws4_private.in_scope(v_i.organisation_id) AND
     (v_i.assigned_dispatcher_user_id=auth.uid() OR v_role IN ('admin','supervisor'))
     AND v_role IN ('admin','dispatcher','supervisor') THEN
    RETURN CASE WHEN v_role IN ('admin','supervisor') THEN 'supervisor' ELSE 'dispatch' END;
  END IF;
  IF public.corvia_ems_member(v_link.hospital_id) IS NOT NULL AND EXISTS
    (SELECT 1 FROM public.corvia_ws6_incident_assignments_actual a
     JOIN public.corvia_ws6_crews c ON c.hospital_id=a.hospital_id
       AND c.crew_id=a.crew_id AND c.crew_status='Active'
       AND c.start_datetime<=now() AND c.end_datetime>now()
     JOIN public.corvia_ws6_shifts_actual sh ON sh.hospital_id=c.hospital_id
       AND sh.shift_id=c.shift_id AND sh.shift_status='Active'
       AND sh.start_datetime<=now() AND sh.end_datetime>now()
     JOIN public.corvia_ws6_crew_members_actual cm ON cm.hospital_id=c.hospital_id
       AND cm.crew_id=c.crew_id AND cm.is_active AND cm.left_datetime IS NULL
     WHERE a.hospital_id=v_link.hospital_id
       AND a.incident_id=v_link.ems_incident_id AND a.is_active
       AND cm.member_id=public.corvia_ems_member(v_link.hospital_id)) THEN
    RETURN 'primary';
  END IF;
  IF EXISTS(SELECT 1 FROM ws4_private.ems_backups b
    JOIN public.corvia_ws6_crew_members_actual cm
      ON cm.hospital_id=b.hospital_id AND cm.crew_id=b.crew_id
      AND cm.is_active AND cm.left_datetime IS NULL
    JOIN public.corvia_ws6_crews c ON c.hospital_id=b.hospital_id
      AND c.crew_id=b.crew_id AND c.crew_status='Active'
      AND c.start_datetime<=now() AND c.end_datetime>now()
    WHERE b.ws4_incident_id=p_ws4 AND b.state IN
      ('offered','acknowledged','en_route','on_scene')
      AND cm.member_id=public.corvia_ems_member(b.hospital_id)) THEN
    RETURN 'backup';
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION public.corvia_ws4_team_linked_id(p_hospital_id uuid,p_ems_incident_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_ws4 bigint;
BEGIN
  SELECT ws4_incident_id INTO v_ws4 FROM ws4_private.ems_handoff_links
    WHERE hospital_id=p_hospital_id AND ems_incident_id=p_ems_incident_id;
  IF NOT FOUND OR ws4_private.linked_actor(v_ws4) IS NULL THEN
    RAISE EXCEPTION 'Linked team access denied' USING ERRCODE='42501';
  END IF;
  RETURN v_ws4::text;
END $$;

CREATE FUNCTION public.corvia_ws4_team_snapshot(p_ws4_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_link ws4_private.ems_handoff_links%ROWTYPE; v_e public.corvia_ws6_incidents_actual%ROWTYPE;
  v_role text; v_units jsonb; v_facilities jsonb; v_exceptions jsonb; v_selected jsonb;
BEGIN
  v_role:=ws4_private.linked_actor(p_ws4_incident_id);
  IF v_role IS NULL THEN RAISE EXCEPTION 'Linked team access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_ws4_incident_id;
  SELECT * INTO v_e FROM public.corvia_ws6_incidents_actual
    WHERE hospital_id=v_link.hospital_id AND incident_id=v_link.ems_incident_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('unit_id',u.unit_id::text,
    'unit_number',u.unit_number,'role',t.role,'latitude',u.latitude,
    'longitude',u.longitude,'location_at',u.location_updated_at,
    'location_stale',u.location_updated_at IS NULL
      OR u.location_updated_at<now()-interval '5 minutes',
    'position_source','Fleet recorded location') ORDER BY t.role),'[]'::jsonb)
    INTO v_units FROM (
      SELECT c.unit_id,'primary' AS role FROM public.corvia_ws6_incident_assignments_actual a
      JOIN public.corvia_ws6_crews c ON c.crew_id=a.crew_id AND c.hospital_id=a.hospital_id
      WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_link.ems_incident_id AND a.is_active
      UNION ALL
      SELECT b.unit_id,'backup' FROM ws4_private.ems_backups b
      WHERE b.ws4_incident_id=p_ws4_incident_id AND b.state IN
        ('offered','acknowledged','en_route','on_scene')
    ) t JOIN public.corvia_ws6_units_actual u ON u.unit_id=t.unit_id
      AND u.hospital_id=v_link.hospital_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('facility_id',f.facility_id::text,
    'name',f.facility_name,'address',f.address,'phone',f.phone_number)
    ORDER BY f.facility_name),'[]'::jsonb) INTO v_facilities
    FROM public.corvia_ws6_receiving_facilities f
    WHERE f.hospital_id=v_link.hospital_id AND f.is_active;
  SELECT to_jsonb(d) INTO v_selected FROM ws4_private.ems_team_destinations d
    WHERE d.ems_incident_id=v_link.ems_incident_id AND d.hospital_id=v_link.hospital_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id::text,'kind',x.kind,
    'reason',x.reason,'recorded_at',x.recorded_at) ORDER BY x.recorded_at),'[]'::jsonb)
    INTO v_exceptions FROM ws4_private.ems_team_exceptions x
    WHERE x.ems_incident_id=v_link.ems_incident_id AND x.active;
  RETURN jsonb_build_object('ws4_incident_id',p_ws4_incident_id::text,
    'ems_incident_id',v_link.ems_incident_id::text,'hospital_id',v_link.hospital_id,
    'revision',v_e.revision::text,'role',v_role,'status',v_e.status,
    'dispatch_state',v_e.dispatch_state,'incident_number',v_e.incident_number,
    'scene_address',v_e.scene_address,'scene_latitude',v_e.latitude,
    'scene_longitude',v_e.longitude,'units',v_units,'facilities',v_facilities,
    'destination',v_selected,'exceptions',v_exceptions,
    'primary_ack_due',v_e.acknowledgement_due_at,
    'primary_overdue',v_e.status='Dispatched' AND v_e.acknowledgement_due_at<=now());
END $$;

CREATE FUNCTION public.corvia_ws4_backup_deadlines(p_ws4_incident_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_items jsonb;
BEGIN
  IF p_ws4_incident_id IS NOT NULL AND
    coalesce(ws4_private.linked_actor(p_ws4_incident_id),'')
      NOT IN ('dispatch','supervisor') THEN
    RAISE EXCEPTION 'Backup timing access denied' USING ERRCODE='42501';
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Backup timing access denied' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('backup_id',b.id::text,
    'due_at',b.acknowledgement_due_at,
    'overdue',b.state='offered' AND b.acknowledgement_due_at<=now())
    ORDER BY b.id),'[]'::jsonb) INTO v_items
  FROM ws4_private.ems_backups b WHERE
    (p_ws4_incident_id IS NOT NULL AND b.ws4_incident_id=p_ws4_incident_id) OR
    (p_ws4_incident_id IS NULL AND b.state IN
      ('offered','acknowledged','en_route','on_scene')
      AND ws4_private.backup_message_actor(b.id)='backup');
  RETURN jsonb_build_object('items',v_items);
END $$;

CREATE FUNCTION public.corvia_ws4_team_completion_command(
  p_ws4_incident_id bigint,p_operation_id uuid,p_expected_revision bigint,
  p_action text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_link ws4_private.ems_handoff_links%ROWTYPE;
  v_e public.corvia_ws6_incidents_actual%ROWTYPE;
  v_old ws4_private.ems_team_receipts%ROWTYPE;
  v_x ws4_private.ems_team_exceptions%ROWTYPE;
  v_role text; v_reason text; v_facility bigint; v_assignment bigint;
  v_unit bigint; v_result jsonb; v_id bigint;
BEGIN
  IF auth.uid() IS NULL OR p_operation_id IS NULL OR
     p_operation_id='00000000-0000-0000-0000-000000000000' OR
     p_expected_revision IS NULL OR p_expected_revision<1 OR
     p_action NOT IN ('destination','exception','resolve_exception',
       'terminal_exception','release_primary') OR
     p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' THEN
    RAISE EXCEPTION 'Valid linked team action and operation required' USING ERRCODE='22023';
  END IF;
  v_reason:=p_payload->>'reason';
  IF v_reason IS NULL OR length(btrim(v_reason))<5 OR length(v_reason)>1000 THEN
    RAISE EXCEPTION 'A bounded reason is required' USING ERRCODE='22023';
  END IF;
  v_role:=ws4_private.linked_actor(p_ws4_incident_id);
  IF v_role IS NULL OR v_role='backup' THEN
    RAISE EXCEPTION 'Linked team command access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_ws4_incident_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_link.hospital_id::text,0));
  SELECT * INTO v_e FROM public.corvia_ws6_incidents_actual
    WHERE hospital_id=v_link.hospital_id AND incident_id=v_link.ems_incident_id FOR UPDATE;
  SELECT * INTO v_old FROM ws4_private.ems_team_receipts
    WHERE actor=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.action<>p_action OR v_old.payload<>p_payload THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  IF v_e.status='Closed' OR v_e.revision<>p_expected_revision THEN
    RAISE EXCEPTION 'Team incident changed; refresh' USING ERRCODE='P0001';
  END IF;
  IF p_action='destination' THEN
    IF v_role NOT IN ('dispatch','supervisor','primary') THEN
      RAISE EXCEPTION 'Destination access denied' USING ERRCODE='42501';
    END IF;
    v_facility:=(p_payload->>'facility_id')::bigint;
    IF NOT EXISTS(SELECT 1 FROM public.corvia_ws6_receiving_facilities f
      WHERE f.hospital_id=v_link.hospital_id AND f.facility_id=v_facility AND f.is_active)
      OR (v_e.status IN ('Transporting','At Hospital','Handed Over') AND NOT EXISTS
        (SELECT 1 FROM ws4_private.ems_team_exceptions x
         WHERE x.ems_incident_id=v_e.incident_id AND x.kind='handover_failed' AND x.active)) THEN
      RAISE EXCEPTION 'Choose an active facility before transport, or record failed handover'
        USING ERRCODE='P0001';
    END IF;
    SELECT id INTO v_id FROM ws4_private.ems_team_exceptions
      WHERE ems_incident_id=v_e.incident_id AND kind='handover_failed' AND active;
    IF v_id IS NOT NULL THEN
      INSERT INTO ws4_private.ems_failed_handovers(handover_id,exception_id)
      SELECT ho.handover_id,v_id FROM public.corvia_ws6_handovers ho
      WHERE ho.hospital_id=v_link.hospital_id AND ho.incident_id=v_e.incident_id
        AND NOT ho.acknowledged ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO ws4_private.ems_team_destinations
      (hospital_id,ems_incident_id,facility_id,chosen_by,reason)
      VALUES(v_link.hospital_id,v_e.incident_id,v_facility,auth.uid(),v_reason)
    ON CONFLICT(ems_incident_id) DO UPDATE SET facility_id=excluded.facility_id,
      chosen_by=excluded.chosen_by,reason=excluded.reason,selected_at=now(),
      revision=ws4_private.ems_team_destinations.revision+1;
    v_result:=jsonb_build_object('facility_id',v_facility::text);
  ELSIF p_action='exception' THEN
    IF p_payload->>'kind' NOT IN ('no_resource','multiple_patients','handover_failed')
       OR (p_payload->>'kind'='no_resource' AND v_role NOT IN ('dispatch','supervisor'))
       OR (p_payload->>'kind'='handover_failed' AND v_e.status NOT IN
         ('At Hospital','Handed Over')) THEN
      RAISE EXCEPTION 'Invalid exception for this incident state' USING ERRCODE='P0001';
    END IF;
    INSERT INTO ws4_private.ems_team_exceptions
      (hospital_id,ems_incident_id,kind,reason,recorded_by,destination_at_record)
    VALUES(v_link.hospital_id,v_e.incident_id,p_payload->>'kind',v_reason,auth.uid(),
      (SELECT d.facility_id FROM ws4_private.ems_team_destinations d
       WHERE d.ems_incident_id=v_e.incident_id)) RETURNING id INTO v_id;
    UPDATE public.corvia_ws6_incidents_actual SET dispatch_state='escalated'
      WHERE hospital_id=v_link.hospital_id AND incident_id=v_e.incident_id;
    v_result:=jsonb_build_object('exception_id',v_id::text,'kind',p_payload->>'kind');
  ELSIF p_action IN ('resolve_exception','terminal_exception') THEN
    IF v_role<>'supervisor' THEN
      RAISE EXCEPTION 'Supervisor review required' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_x FROM ws4_private.ems_team_exceptions
      WHERE id=(p_payload->>'exception_id')::bigint
        AND hospital_id=v_link.hospital_id AND ems_incident_id=v_e.incident_id
        AND active FOR UPDATE;
    IF NOT FOUND OR v_x.recorded_by=auth.uid() THEN
      RAISE EXCEPTION 'Independent supervisor review required' USING ERRCODE='P0001';
    END IF;
    IF p_action='resolve_exception' AND v_x.kind='handover_failed'
      AND NOT EXISTS(SELECT 1 FROM ws4_private.ems_team_destinations d
        WHERE d.ems_incident_id=v_e.incident_id
          AND d.facility_id IS DISTINCT FROM v_x.destination_at_record) THEN
      RAISE EXCEPTION 'Choose a different active receiving facility first'
        USING ERRCODE='P0001';
    END IF;
    IF p_action='resolve_exception' AND v_x.kind='no_resource'
      AND NOT EXISTS(SELECT 1 FROM public.corvia_ws6_incident_assignments_actual a
        WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_e.incident_id
          AND a.is_active) THEN
      RAISE EXCEPTION 'Assign an eligible crew before resolving no-resource escalation'
        USING ERRCODE='P0001';
    END IF;
    IF p_action='terminal_exception' AND v_x.kind NOT IN ('no_patient','refusal') THEN
      RAISE EXCEPTION 'This exception cannot end the incident without handover'
        USING ERRCODE='P0001';
    END IF;
    IF p_action='terminal_exception' AND
       (EXISTS(SELECT 1 FROM ws4_private.ems_backups b
          WHERE b.ems_incident_id=v_e.incident_id AND b.state IN
            ('offered','acknowledged','en_route','on_scene')) OR
        (v_x.kind='no_patient' AND EXISTS
          (SELECT 1 FROM public.corvia_ws6_incident_patients ip
           WHERE ip.incident_id=v_e.incident_id AND ip.is_active))) THEN
      RAISE EXCEPTION 'Release backup and review patient disposition first'
        USING ERRCODE='P0001';
    END IF;
    UPDATE ws4_private.ems_team_exceptions SET active=false,
      resolved_by=auth.uid(),resolved_at=now(),resolution=v_reason WHERE id=v_x.id;
    v_result:=jsonb_build_object('exception_id',v_x.id::text,'resolved',true);
    IF p_action='terminal_exception' THEN
      IF EXISTS(SELECT 1 FROM ws4_private.ems_team_exceptions x
        WHERE x.ems_incident_id=v_e.incident_id AND x.active) THEN
        RAISE EXCEPTION 'Resolve other safety exceptions first' USING ERRCODE='P0001';
      END IF;
      UPDATE public.corvia_ws6_incident_assignments_actual SET is_active=false,
        assignment_status='Completed' WHERE hospital_id=v_link.hospital_id
        AND incident_id=v_e.incident_id AND is_active;
      UPDATE public.corvia_ws6_units_actual u SET status='Available',
        availability_revision=availability_revision+1
        WHERE u.hospital_id=v_link.hospital_id AND u.unit_id IN
          (SELECT c.unit_id FROM public.corvia_ws6_crews c JOIN
           public.corvia_ws6_incident_assignments_actual a ON a.crew_id=c.crew_id
           WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_e.incident_id);
      UPDATE public.corvia_ws6_incidents_actual SET status='Closed',closed_datetime=now(),
        dispatch_state='cancelled',acknowledgement_due_at=NULL
        WHERE hospital_id=v_link.hospital_id AND incident_id=v_e.incident_id;
      INSERT INTO public.corvia_ws6_incident_status_history
        (hospital_id,incident_id,status,status_datetime,sync_status,sent_at)
      VALUES(v_link.hospital_id,v_e.incident_id,'Closed',now(),'Sent',now());
      v_result:=v_result||jsonb_build_object('status','Closed','dispatch_state','cancelled');
    ELSE
      UPDATE public.corvia_ws6_incidents_actual SET dispatch_state=CASE
        WHEN EXISTS(SELECT 1 FROM public.corvia_ws6_incident_assignments_actual a
          WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_e.incident_id
          AND a.is_active) THEN 'assigned' ELSE 'escalated' END
        WHERE hospital_id=v_link.hospital_id AND incident_id=v_e.incident_id;
    END IF;
  ELSE
    IF v_role NOT IN ('dispatch','supervisor') THEN
      RAISE EXCEPTION 'Dispatch release required' USING ERRCODE='42501';
    END IF;
    IF v_role<>'supervisor' AND
       (v_e.status<>'Dispatched' OR v_e.acknowledgement_due_at>now()) THEN
      RAISE EXCEPTION 'Only a supervisor may withdraw an active primary response'
        USING ERRCODE='P0001';
    END IF;
    SELECT a.assignment_id,c.unit_id INTO v_assignment,v_unit
      FROM public.corvia_ws6_incident_assignments_actual a
      JOIN public.corvia_ws6_crews c ON c.crew_id=a.crew_id
        AND c.hospital_id=a.hospital_id
      WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_e.incident_id
        AND a.is_active FOR UPDATE OF a;
    IF v_assignment IS NULL OR v_e.status NOT IN
       ('Dispatched','Accepted','En Route','On Scene') THEN
      RAISE EXCEPTION 'No releasable primary response' USING ERRCODE='P0001';
    END IF;
    UPDATE public.corvia_ws6_incident_assignments_actual
      SET is_active=false,assignment_status='Declined' WHERE assignment_id=v_assignment;
    UPDATE public.corvia_ws6_units_actual SET status='Available',
      availability_revision=availability_revision+1
      WHERE hospital_id=v_link.hospital_id AND unit_id=v_unit;
    UPDATE public.corvia_ws6_incidents_actual SET dispatch_state='escalated',
      acknowledgement_due_at=NULL WHERE hospital_id=v_link.hospital_id
      AND incident_id=v_e.incident_id;
    v_result:=jsonb_build_object('released_assignment_id',v_assignment::text);
  END IF;
  UPDATE public.corvia_ws6_incidents_actual SET revision=revision+1
    WHERE hospital_id=v_link.hospital_id AND incident_id=v_e.incident_id;
  v_result:=v_result||jsonb_build_object('operation_id',p_operation_id,
    'action',p_action,'revision',(v_e.revision+1)::text);
  INSERT INTO ws4_private.ems_team_receipts(actor,operation_id,action,payload,result)
    VALUES(auth.uid(),p_operation_id,p_action,p_payload,v_result);
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,
     entity_id,new_value,reason)
    VALUES(v_link.hospital_id,auth.uid(),v_e.incident_id,'ws4_'||p_action,
      'incident',v_e.incident_id,v_result,v_reason);
  RETURN v_result;
END $$;

CREATE TABLE ws4_private.ems_backup_messages (
  message_id bigint PRIMARY KEY REFERENCES public.corvia_ops_messages(message_id),
  backup_id bigint NOT NULL REFERENCES ws4_private.ems_backups(id)
);
CREATE TABLE ws4_private.ems_backup_message_reads (
  message_id bigint NOT NULL REFERENCES ws4_private.ems_backup_messages(message_id),
  reader uuid NOT NULL REFERENCES auth.users(id), read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(message_id,reader)
);
ALTER TABLE ws4_private.ems_backup_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_backup_message_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.ems_backup_messages,ws4_private.ems_backup_message_reads
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION ws4_private.backup_message_actor(p_backup bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_b ws4_private.ems_backups%ROWTYPE; v_role text;
BEGIN
  SELECT * INTO v_b FROM ws4_private.ems_backups WHERE id=p_backup;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_role:=ws4_private.linked_actor(v_b.ws4_incident_id);
  IF v_role IN ('dispatch','supervisor') THEN RETURN 'dispatch'; END IF;
  IF v_role='backup' AND v_b.state IN
    ('offered','acknowledged','en_route','on_scene') AND EXISTS
    (SELECT 1 FROM public.corvia_ws6_crew_members_actual cm
     WHERE cm.hospital_id=v_b.hospital_id AND cm.crew_id=v_b.crew_id
       AND cm.is_active AND cm.left_datetime IS NULL
       AND cm.member_id=public.corvia_ems_member(v_b.hospital_id)) THEN
    RETURN 'backup';
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION public.corvia_ws4_backup_conversation(p_backup_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_messages jsonb;
BEGIN
  IF ws4_private.backup_message_actor(p_backup_id) IS NULL THEN
    RAISE EXCEPTION 'Backup conversation access denied' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',m.message_id::text,
    'sender',CASE WHEN m.sender=auth.uid() THEN 'you' ELSE 'team' END,
    'body',m.message,'saved_at',m.received_at,
    'read_by_other',EXISTS(SELECT 1 FROM ws4_private.ems_backup_message_reads r
      WHERE r.message_id=m.message_id AND r.reader<>m.sender))
    ORDER BY m.message_id),'[]'::jsonb) INTO v_messages
    FROM (SELECT mm.* FROM ws4_private.ems_backup_messages bm
      JOIN public.corvia_ops_messages mm ON mm.message_id=bm.message_id
      WHERE bm.backup_id=p_backup_id ORDER BY bm.message_id DESC LIMIT 50) m;
  RETURN jsonb_build_object('backup_id',p_backup_id::text,'messages',v_messages);
END $$;

CREATE FUNCTION public.corvia_ws4_backup_message(
  p_backup_id bigint,p_operation_id uuid,p_body text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_b ws4_private.ems_backups%ROWTYPE; v_old ws4_private.ems_team_receipts%ROWTYPE;
  v_payload jsonb; v_result jsonb; v_id bigint;
BEGIN
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000'
    OR p_body IS NULL OR length(btrim(p_body))<1 OR length(p_body)>2000 THEN
    RAISE EXCEPTION 'Valid backup message required' USING ERRCODE='22023';
  END IF;
  IF ws4_private.backup_message_actor(p_backup_id) IS NULL THEN
    RAISE EXCEPTION 'Backup conversation access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_b FROM ws4_private.ems_backups WHERE id=p_backup_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_b.hospital_id::text,0));
  SELECT * INTO v_b FROM ws4_private.ems_backups WHERE id=p_backup_id FOR UPDATE;
  IF ws4_private.backup_message_actor(p_backup_id) IS NULL OR
     v_b.state NOT IN ('offered','acknowledged','en_route','on_scene') THEN
    RAISE EXCEPTION 'Backup conversation access changed' USING ERRCODE='42501';
  END IF;
  v_payload:=jsonb_build_object('backup_id',p_backup_id::text,'body',p_body);
  SELECT * INTO v_old FROM ws4_private.ems_team_receipts
    WHERE actor=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.action<>'backup_message' OR v_old.payload<>v_payload THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  INSERT INTO public.corvia_ops_messages
    (hospital_id,incident_id,sender,message,recorded_at)
  VALUES(v_b.hospital_id,v_b.ems_incident_id,auth.uid(),p_body,now())
  RETURNING message_id INTO v_id;
  INSERT INTO ws4_private.ems_backup_messages VALUES(v_id,p_backup_id);
  v_result:=jsonb_build_object('backup_id',p_backup_id::text,'message_id',v_id::text,
    'operation_id',p_operation_id,'saved',true);
  INSERT INTO ws4_private.ems_team_receipts(actor,operation_id,action,payload,result)
    VALUES(auth.uid(),p_operation_id,'backup_message',v_payload,v_result);
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,
     entity_id,new_value)
  VALUES(v_b.hospital_id,auth.uid(),v_b.ems_incident_id,'backup_message',
    'message',v_id,jsonb_build_object('message_id',v_id::text));
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_backup_mark_read(p_message_id bigint,p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_backup bigint; v_sender uuid; v_old ws4_private.ems_team_receipts%ROWTYPE;
  v_payload jsonb; v_result jsonb;
BEGIN
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000'
     THEN RAISE EXCEPTION 'Valid read operation required' USING ERRCODE='22023'; END IF;
  SELECT bm.backup_id,m.sender INTO v_backup,v_sender
    FROM ws4_private.ems_backup_messages bm JOIN public.corvia_ops_messages m
      ON m.message_id=bm.message_id WHERE bm.message_id=p_message_id;
  IF NOT FOUND OR ws4_private.backup_message_actor(v_backup) IS NULL
    OR v_sender=auth.uid() THEN
    RAISE EXCEPTION 'Backup message access denied' USING ERRCODE='42501';
  END IF;
  v_payload:=jsonb_build_object('message_id',p_message_id::text);
  SELECT * INTO v_old FROM ws4_private.ems_team_receipts
    WHERE actor=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.action<>'backup_read' OR v_old.payload<>v_payload THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023'; END IF;
    RETURN v_old.result;
  END IF;
  INSERT INTO ws4_private.ems_backup_message_reads(message_id,reader)
    VALUES(p_message_id,auth.uid()) ON CONFLICT DO NOTHING;
  v_result:=jsonb_build_object('message_id',p_message_id::text,
    'operation_id',p_operation_id,'read',true);
  INSERT INTO ws4_private.ems_team_receipts(actor,operation_id,action,payload,result)
    VALUES(auth.uid(),p_operation_id,'backup_read',v_payload,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_callback_outcome(
  p_incident_id bigint,p_operation_id uuid,p_expected_version bigint,
  p_command text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text; v_i public.incidents%ROWTYPE;
  v_old ws4_private.dispatch_commands%ROWTYPE; v_result jsonb;
BEGIN
  v_role:=ws4_private.lock_workspace(p_incident_id);
  IF p_command<>'callback_outcome' OR p_operation_id IS NULL OR
     p_operation_id='00000000-0000-0000-0000-000000000000' OR
     p_expected_version IS NULL OR p_expected_version<1 OR
     p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR
     (p_payload-'outcome'-'text')<>'{}'::jsonb OR
     coalesce(p_payload->>'outcome','') NOT IN
       ('connected','no_answer','failed','not_attempted') OR
     length(btrim(coalesce(p_payload->>'text','')))<5 OR
     length(p_payload->>'text')>1000 THEN
    RAISE EXCEPTION 'Valid callback outcome and reason required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    auth.uid()::text||':command:'||p_operation_id::text,0));
  SELECT * INTO v_old FROM ws4_private.dispatch_commands
    WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (v_old.incident_id,v_old.expected_version,v_old.command,v_old.payload)
       IS DISTINCT FROM
       (p_incident_id,p_expected_version,p_command,p_payload) THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  IF NOT FOUND OR v_i.version<>p_expected_version OR
     v_i.status<>'in_progress' OR v_role='patient' OR NOT
     (v_i.assigned_dispatcher_user_id=auth.uid() OR v_role='dispatch_supervisor') THEN
    RAISE EXCEPTION 'Current dispatch owner or supervisor required'
      USING ERRCODE='42501';
  END IF;
  UPDATE public.incidents SET status=status WHERE id=p_incident_id RETURNING * INTO v_i;
  v_result:=jsonb_build_object('incident_id',v_i.id::text,
    'operation_id',p_operation_id,'version',v_i.version::text,'command',p_command);
  INSERT INTO ws4_private.dispatch_commands
    (actor_id,operation_id,incident_id,expected_version,command,payload,result)
  VALUES(auth.uid(),p_operation_id,p_incident_id,p_expected_version,
    p_command,p_payload,v_result);
  RETURN v_result;
END $$;

-- Can be scheduled by the owner. Repeated execution and worker restarts are safe.
-- The worker flags overdue offers; it never falsely accepts or releases a crew.
CREATE FUNCTION public.corvia_ws4_team_deadline_scan()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_count integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS NOT NULL
     AND current_setting('request.jwt.claim.role',true)<>'service_role' THEN
    RAISE EXCEPTION 'Deadline worker access denied' USING ERRCODE='42501';
  END IF;
  WITH due AS (
    SELECT 'primary'::text AS kind,a.assignment_id AS resource_id,
      e.hospital_id,e.incident_id
    FROM public.corvia_ws6_incident_assignments_actual a
    JOIN public.corvia_ws6_incidents_actual e ON e.incident_id=a.incident_id
      AND e.hospital_id=a.hospital_id
    JOIN ws4_private.ems_handoff_links l ON l.ems_incident_id=e.incident_id
      AND l.hospital_id=e.hospital_id
    WHERE a.is_active AND e.status='Dispatched' AND e.acknowledgement_due_at<=now()
    UNION ALL
    SELECT 'backup',b.id,b.hospital_id,b.ems_incident_id
    FROM ws4_private.ems_backups b WHERE b.state='offered'
      AND b.acknowledgement_due_at<=now()
  ), inserted AS (
    INSERT INTO ws4_private.ems_team_deadline_alerts
      (kind,resource_id,hospital_id,ems_incident_id)
    SELECT kind,resource_id,hospital_id,incident_id FROM due
    ON CONFLICT DO NOTHING RETURNING *)
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,incident_id,action_type,entity_type,entity_id,new_value)
  SELECT hospital_id,ems_incident_id,'ws4_ack_overdue',kind,resource_id,
    jsonb_build_object('kind',kind,'overdue',true)
  FROM inserted;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count;
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_team_linked_id(uuid,bigint),
  public.corvia_ws4_team_snapshot(bigint),
  public.corvia_ws4_backup_deadlines(bigint),
  public.corvia_ws4_team_completion_command(bigint,uuid,bigint,text,jsonb),
  public.corvia_ws4_backup_conversation(bigint),
  public.corvia_ws4_backup_message(bigint,uuid,text),
  public.corvia_ws4_backup_mark_read(bigint,uuid),
  public.corvia_ws4_callback_outcome(bigint,uuid,bigint,text,jsonb),
  public.corvia_ws4_team_deadline_scan()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_team_linked_id(uuid,bigint),
  public.corvia_ws4_team_snapshot(bigint),
  public.corvia_ws4_backup_deadlines(bigint),
  public.corvia_ws4_team_completion_command(bigint,uuid,bigint,text,jsonb),
  public.corvia_ws4_backup_conversation(bigint),
  public.corvia_ws4_backup_message(bigint,uuid,text),
  public.corvia_ws4_backup_mark_read(bigint,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_callback_outcome(bigint,uuid,bigint,text,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_team_deadline_scan() TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
