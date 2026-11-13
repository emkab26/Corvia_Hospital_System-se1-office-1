-- WS4 additions to the reviewed team EMS bridge. Install after 003 as owner.
-- Team Fleet/Paramedic tables and command definitions remain authoritative.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $$ BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_private.ems_handoff_links') IS NULL
     OR to_regprocedure('public.corvia_ws4_close_incident(bigint,uuid,bigint,text,jsonb)') IS NULL
     OR to_regclass('public.corvia_ws6_incident_assignments_actual') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4/team EMS bridge and team schema required';
  END IF;
  IF to_regclass('ws4_private.ems_backups') IS NOT NULL THEN
    RAISE EXCEPTION 'WS4 team backup/receiver addendum already installed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.corvia_ws6_handovers ho
    JOIN ws4_private.ems_handoff_links l
      ON l.ems_incident_id=ho.incident_id AND l.hospital_id=ho.hospital_id
    WHERE ho.acknowledged) THEN
    RAISE EXCEPTION 'Review existing linked handover acknowledgements before installing independent receipt enforcement';
  END IF;
END $$;

-- Owner-provisioned receiving users. A facility is a directory entry, not
-- evidence of admission or receipt; only its mapped user can confirm a handover.
CREATE TABLE ws4_private.ems_receivers (
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  facility_id bigint NOT NULL REFERENCES public.corvia_ws6_receiving_facilities(facility_id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  active boolean NOT NULL DEFAULT false,
  granted_by uuid NOT NULL REFERENCES auth.users(id),
  PRIMARY KEY (hospital_id,facility_id,user_id)
);
CREATE TABLE ws4_private.ems_receiver_receipts (
  user_id uuid NOT NULL, operation_id uuid NOT NULL,
  handover_id bigint NOT NULL REFERENCES public.corvia_ws6_handovers(handover_id),
  reason text NOT NULL,
  result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,operation_id)
);
CREATE UNIQUE INDEX ems_one_receiver_ack_per_handover
  ON ws4_private.ems_receiver_receipts(handover_id);

-- A backup is deliberately separate from the team's single-primary-assignment
-- table. It reserves a real team unit and verified crew without changing the
-- team's clinical status command, which assumes exactly one primary crew.
CREATE TABLE ws4_private.ems_backups (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ws4_incident_id bigint NOT NULL REFERENCES public.incidents(id),
  hospital_id uuid NOT NULL REFERENCES public.hospitals(id),
  ems_incident_id bigint NOT NULL REFERENCES public.corvia_ws6_incidents_actual(incident_id),
  crew_id bigint NOT NULL REFERENCES public.corvia_ws6_crews(crew_id),
  unit_id bigint NOT NULL REFERENCES public.corvia_ws6_units_actual(unit_id),
  state text NOT NULL CHECK (state IN
    ('offered','acknowledged','en_route','on_scene','declined','released')),
  version bigint NOT NULL DEFAULT 1 CHECK (version>0),
  reason text NOT NULL, offered_by uuid NOT NULL,
  offered_at timestamptz NOT NULL DEFAULT now(),
  answered_at timestamptz, released_at timestamptz
);
CREATE UNIQUE INDEX ems_one_active_backup_per_incident
  ON ws4_private.ems_backups(ems_incident_id)
  WHERE state IN ('offered','acknowledged','en_route','on_scene');
CREATE UNIQUE INDEX ems_one_active_backup_per_unit
  ON ws4_private.ems_backups(unit_id)
  WHERE state IN ('offered','acknowledged','en_route','on_scene');
CREATE UNIQUE INDEX ems_one_active_backup_per_crew
  ON ws4_private.ems_backups(crew_id)
  WHERE state IN ('offered','acknowledged','en_route','on_scene');
CREATE TABLE ws4_private.ems_backup_receipts (
  user_id uuid NOT NULL, operation_id uuid NOT NULL,
  backup_id bigint REFERENCES ws4_private.ems_backups(id),
  action text NOT NULL, payload jsonb NOT NULL,
  result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,operation_id)
);
ALTER TABLE ws4_private.ems_receivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_receiver_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.ems_backup_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.ems_receivers,ws4_private.ems_receiver_receipts,
  ws4_private.ems_backups,ws4_private.ems_backup_receipts FROM PUBLIC,anon,authenticated;

CREATE FUNCTION ws4_private.receiver_allowed(p_hospital uuid,p_facility bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM ws4_private.ems_receivers r
    JOIN public.profiles p ON p.user_id=r.user_id AND p.is_active
    JOIN public.hospitals h ON h.id=r.hospital_id AND h.is_active
    JOIN public.corvia_ws6_receiving_facilities f
      ON f.facility_id=r.facility_id AND f.hospital_id=r.hospital_id AND f.is_active
    WHERE r.hospital_id=p_hospital AND r.facility_id=p_facility
      AND r.user_id=auth.uid() AND r.active
  );
$$;

-- Even the existing team command cannot self-acknowledge a linked handover.
CREATE FUNCTION ws4_private.guard_receiver_ack() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.acknowledged AND NOT OLD.acknowledged
     AND EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links l
                 WHERE l.ems_incident_id=NEW.incident_id AND l.hospital_id=NEW.hospital_id) THEN
    IF NOT ws4_private.receiver_allowed(NEW.hospital_id,NEW.facility_id)
       OR EXISTS (SELECT 1 FROM public.corvia_ws6_ems_members m
                  WHERE m.member_id=NEW.completed_by AND m.auth_user_id=auth.uid()) THEN
      RAISE EXCEPTION 'Independent receiving user confirmation required'
        USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_independent_receiver_guard
BEFORE UPDATE OF acknowledged ON public.corvia_ws6_handovers
FOR EACH ROW EXECUTE FUNCTION ws4_private.guard_receiver_ack();

-- Team closure must wait for any backup to stand down and for receiver evidence.
CREATE FUNCTION ws4_private.guard_team_completion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('Handed Over','Closed')
     AND EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links l
                 WHERE l.ems_incident_id=NEW.incident_id AND l.hospital_id=NEW.hospital_id) THEN
    IF EXISTS (SELECT 1 FROM ws4_private.ems_backups b
               WHERE b.ems_incident_id=NEW.incident_id AND b.hospital_id=NEW.hospital_id
                 AND b.state IN ('offered','acknowledged','en_route','on_scene')) THEN
      RAISE EXCEPTION 'Release the active backup before team completion'
        USING ERRCODE='P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM public.corvia_ws6_handovers ho
               WHERE ho.incident_id=NEW.incident_id AND ho.hospital_id=NEW.hospital_id
                 AND ho.acknowledged AND NOT EXISTS (
                   SELECT 1 FROM ws4_private.ems_receiver_receipts rr
                   WHERE rr.handover_id=ho.handover_id)) THEN
      RAISE EXCEPTION 'Independent receiver evidence required before completion'
        USING ERRCODE='P0001';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_team_completion_guard
BEFORE UPDATE OF status ON public.corvia_ws6_incidents_actual
FOR EACH ROW EXECUTE FUNCTION ws4_private.guard_team_completion();

CREATE FUNCTION public.corvia_ws4_receiver_inbox()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_items jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in to view receiving handovers' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'handover_id',ho.handover_id::text,'incident_number',e.incident_number,
    'facility_name',f.facility_name,'receiver_name',ho.receiver_name,
    'handover_summary',ho.handover_summary,'handover_at',ho.handover_datetime,
    'acknowledged',ho.acknowledged,'acknowledged_at',ho.acknowledged_datetime)
    ORDER BY ho.handover_datetime DESC),'[]'::jsonb) INTO v_items
  FROM public.corvia_ws6_handovers ho
  JOIN ws4_private.ems_handoff_links l
    ON l.ems_incident_id=ho.incident_id AND l.hospital_id=ho.hospital_id
  JOIN public.corvia_ws6_incidents_actual e
    ON e.incident_id=ho.incident_id AND e.hospital_id=ho.hospital_id
  JOIN public.corvia_ws6_receiving_facilities f
    ON f.facility_id=ho.facility_id AND f.hospital_id=ho.hospital_id
  WHERE ws4_private.receiver_allowed(ho.hospital_id,ho.facility_id);
  RETURN jsonb_build_object('items',v_items);
END $$;

CREATE FUNCTION public.corvia_ws4_team_case_mode(p_hospital_id uuid,p_incident_id bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.corvia_ems_allowed(p_hospital_id,p_incident_id) THEN
    RAISE EXCEPTION 'Team incident access denied' USING ERRCODE='42501';
  END IF;
  RETURN EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links l
    WHERE l.hospital_id=p_hospital_id AND l.ems_incident_id=p_incident_id);
END $$;

CREATE FUNCTION public.corvia_ws4_receiver_ack(
  p_handover_id bigint,p_operation_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_ho public.corvia_ws6_handovers%ROWTYPE; v_old ws4_private.ems_receiver_receipts%ROWTYPE;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_operation_id IS NULL
     OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR p_reason IS NULL OR length(btrim(p_reason))<5 OR length(p_reason)>1000 THEN
    RAISE EXCEPTION 'Confirmation and reason required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_ho FROM public.corvia_ws6_handovers WHERE handover_id=p_handover_id FOR UPDATE;
  IF NOT FOUND OR NOT ws4_private.receiver_allowed(v_ho.hospital_id,v_ho.facility_id)
     OR NOT EXISTS (SELECT 1 FROM ws4_private.ems_handoff_links l
                    WHERE l.ems_incident_id=v_ho.incident_id AND l.hospital_id=v_ho.hospital_id)
     OR EXISTS (SELECT 1 FROM public.corvia_ws6_ems_members m
                WHERE m.member_id=v_ho.completed_by AND m.auth_user_id=auth.uid()) THEN
    RAISE EXCEPTION 'Receiving access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_old FROM ws4_private.ems_receiver_receipts
    WHERE user_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.handover_id<>p_handover_id OR v_old.reason<>p_reason THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  IF v_ho.acknowledged THEN
    RAISE EXCEPTION 'Handover already confirmed' USING ERRCODE='P0001';
  END IF;
  UPDATE public.corvia_ws6_handovers SET acknowledged=true,acknowledged_datetime=now()
    WHERE handover_id=p_handover_id;
  v_result:=jsonb_build_object('handover_id',p_handover_id::text,
    'operation_id',p_operation_id,'acknowledged',true);
  INSERT INTO ws4_private.ems_receiver_receipts
    (user_id,operation_id,handover_id,reason,result)
    VALUES(auth.uid(),p_operation_id,p_handover_id,p_reason,v_result);
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,entity_id,new_value,reason)
    VALUES(v_ho.hospital_id,auth.uid(),v_ho.incident_id,'receiver_confirmed',
      'handover',p_handover_id,v_result,p_reason);
  RETURN v_result;
END $$;

CREATE FUNCTION ws4_private.release_backup_unit(p_hospital uuid,p_unit bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  UPDATE public.corvia_ops_readiness SET expires_at=least(expires_at,now())
    WHERE hospital_id=p_hospital AND unit_id=p_unit;
  UPDATE public.corvia_ws6_units_actual
    SET status=CASE WHEN readiness_status='maintenance' OR EXISTS (
          SELECT 1 FROM public.corvia_ops_faults f WHERE f.hospital_id=p_hospital
            AND f.unit_id=p_unit AND f.resolved_at IS NULL)
        THEN 'Out of Service' ELSE 'Available' END,
        availability_revision=availability_revision+1
    WHERE hospital_id=p_hospital AND unit_id=p_unit;
END $$;

CREATE FUNCTION ws4_private.guard_backup_reservation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status<>'Assigned'
     AND EXISTS (SELECT 1 FROM ws4_private.ems_backups b
       WHERE b.hospital_id=NEW.hospital_id AND b.unit_id=NEW.unit_id
         AND b.state IN ('offered','acknowledged','en_route','on_scene')) THEN
    RAISE EXCEPTION 'Release the active backup before changing unit availability'
      USING ERRCODE='P0001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_backup_unit_reservation_guard
BEFORE UPDATE OF status ON public.corvia_ws6_units_actual
FOR EACH ROW EXECUTE FUNCTION ws4_private.guard_backup_reservation();

CREATE FUNCTION public.corvia_ws4_backup_overview(p_ws4_incident_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_link ws4_private.ems_handoff_links%ROWTYPE; v_i public.incidents%ROWTYPE;
  v_team public.corvia_ws6_incidents_actual%ROWTYPE; v_items jsonb; v_candidates jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in to view backup response' USING ERRCODE='42501';
  END IF;
  IF p_ws4_incident_id IS NULL THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'backup_id',b.id::text,'version',b.version::text,'state',b.state,
      'incident_number',e.incident_number,'scene_address',e.scene_address,
      'priority',e.priority,'reason',b.reason,'offered_at',b.offered_at)
      ORDER BY b.offered_at DESC),'[]'::jsonb) INTO v_items
    FROM ws4_private.ems_backups b
    JOIN public.corvia_ws6_incidents_actual e ON e.incident_id=b.ems_incident_id
      AND e.hospital_id=b.hospital_id
    JOIN public.corvia_ws6_crew_members_actual cm ON cm.crew_id=b.crew_id
      AND cm.hospital_id=b.hospital_id AND cm.is_active AND cm.left_datetime IS NULL
    JOIN public.corvia_ws6_crews c ON c.crew_id=b.crew_id AND c.hospital_id=b.hospital_id
      AND c.crew_status='Active' AND c.start_datetime<=now() AND c.end_datetime>now()
    JOIN public.corvia_ws6_shifts_actual sh ON sh.shift_id=c.shift_id
      AND sh.hospital_id=b.hospital_id AND sh.shift_status='Active'
      AND sh.start_datetime<=now() AND sh.end_datetime>now()
    WHERE b.state IN ('offered','acknowledged','en_route','on_scene')
      AND cm.member_id=public.corvia_ems_member(b.hospital_id);
    RETURN jsonb_build_object('items',v_items);
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_ws4_incident_id;
  IF NOT FOUND OR NOT ws4_private.in_scope(v_i.organisation_id) THEN
    RAISE EXCEPTION 'Dispatch scope denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_ws4_incident_id;
  IF NOT FOUND OR public.corvia_ops_role(v_link.hospital_id)
      NOT IN ('admin','dispatcher','supervisor') THEN
    RAISE EXCEPTION 'Team dispatch access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_team FROM public.corvia_ws6_incidents_actual
    WHERE incident_id=v_link.ems_incident_id AND hospital_id=v_link.hospital_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('backup_id',b.id::text,
    'version',b.version::text,'state',b.state,'crew_code',c.crew_code,
    'unit_number',u.unit_number,'reason',b.reason,'offered_at',b.offered_at)
    ORDER BY b.offered_at DESC),'[]'::jsonb) INTO v_items
  FROM ws4_private.ems_backups b
  JOIN public.corvia_ws6_crews c ON c.crew_id=b.crew_id AND c.hospital_id=b.hospital_id
  JOIN public.corvia_ws6_units_actual u ON u.unit_id=b.unit_id AND u.hospital_id=b.hospital_id
  WHERE b.ws4_incident_id=p_ws4_incident_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('crew_id',c.crew_id::text,
    'crew_code',c.crew_code,'unit_number',u.unit_number,
    'eligibility_reason',public.corvia_ops_eligibility(v_link.hospital_id,u.unit_id,v_team.required_capability))
    ORDER BY c.crew_code),'[]'::jsonb) INTO v_candidates
  FROM public.corvia_ws6_crews c
  JOIN public.corvia_ws6_units_actual u ON u.unit_id=c.unit_id
    AND u.hospital_id=c.hospital_id
  WHERE c.hospital_id=v_link.hospital_id AND c.crew_status='Active'
    AND c.start_datetime<=now() AND c.end_datetime>now();
  RETURN jsonb_build_object('ems_revision',v_team.revision::text,
    'incident_number',v_team.incident_number,'status',v_team.status,
    'backup_requested',EXISTS(SELECT 1 FROM public.corvia_ws6_audit_logs a
      WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_link.ems_incident_id
        AND a.action_type='exception' AND a.new_value->>'exception'='backup_required'),
    'backups',v_items,'candidates',v_candidates);
END $$;

CREATE FUNCTION public.corvia_ws4_backup_dispatch(
  p_ws4_incident_id bigint,p_operation_id uuid,p_expected_revision bigint,
  p_action text,p_crew_id bigint,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_i public.incidents%ROWTYPE; v_link ws4_private.ems_handoff_links%ROWTYPE;
  v_team public.corvia_ws6_incidents_actual%ROWTYPE; v_crew public.corvia_ws6_crews%ROWTYPE;
  v_backup ws4_private.ems_backups%ROWTYPE; v_old ws4_private.ems_backup_receipts%ROWTYPE;
  v_role text; v_result jsonb; v_payload jsonb; v_id bigint;
BEGIN
  IF auth.uid() IS NULL OR p_operation_id IS NULL
     OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR p_expected_revision IS NULL OR p_expected_revision<1
     OR p_action IS NULL OR p_action NOT IN ('offer','release') OR p_reason IS NULL
     OR length(btrim(p_reason))<5 OR length(p_reason)>1000 THEN
    RAISE EXCEPTION 'Valid backup action, revision and reason required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_ws4_incident_id;
  IF NOT FOUND OR NOT ws4_private.in_scope(v_i.organisation_id)
     OR v_i.status<>'in_progress' THEN
    RAISE EXCEPTION 'Dispatch scope denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM ws4_private.ems_handoff_links
    WHERE ws4_incident_id=p_ws4_incident_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Team link required' USING ERRCODE='P0001'; END IF;
  v_role:=public.corvia_ops_role(v_link.hospital_id);
  IF v_role IS NULL OR v_role NOT IN ('admin','dispatcher','supervisor')
     OR (v_i.assigned_dispatcher_user_id IS DISTINCT FROM auth.uid()
         AND v_role NOT IN ('admin','supervisor')) THEN
    RAISE EXCEPTION 'Current dispatch authority required' USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_link.hospital_id::text,0));
  SELECT * INTO v_team FROM public.corvia_ws6_incidents_actual
    WHERE hospital_id=v_link.hospital_id AND incident_id=v_link.ems_incident_id FOR UPDATE;
  v_payload:=jsonb_build_object('incident_id',p_ws4_incident_id::text,
    'revision',p_expected_revision::text,'action',p_action,
    'crew_id',p_crew_id::text,'reason',p_reason);
  SELECT * INTO v_old FROM ws4_private.ems_backup_receipts
    WHERE user_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.action<>p_action OR v_old.payload<>v_payload THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  IF v_team.revision<>p_expected_revision OR v_team.status='Closed' THEN
    RAISE EXCEPTION 'Team incident changed' USING ERRCODE='P0001';
  END IF;
  IF p_action='offer' THEN
    IF v_team.status NOT IN ('Dispatched','Accepted','En Route','On Scene')
       OR NOT EXISTS (SELECT 1 FROM public.corvia_ws6_audit_logs a
         WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_link.ems_incident_id
           AND a.action_type='exception' AND a.new_value->>'exception'='backup_required')
       OR NOT EXISTS (SELECT 1 FROM public.corvia_ws6_incident_assignments_actual a
         WHERE a.hospital_id=v_link.hospital_id AND a.incident_id=v_link.ems_incident_id
           AND a.is_active) THEN
      RAISE EXCEPTION 'Active primary response and recorded backup request required'
        USING ERRCODE='P0001';
    END IF;
    SELECT * INTO v_crew FROM public.corvia_ws6_crews
      WHERE hospital_id=v_link.hospital_id AND crew_id=p_crew_id;
    IF NOT FOUND OR v_crew.crew_status<>'Active' OR v_crew.start_datetime>now()
       OR v_crew.end_datetime<=now()
       OR NOT EXISTS (SELECT 1 FROM public.corvia_ws6_shifts_actual sh
         WHERE sh.shift_id=v_crew.shift_id AND sh.hospital_id=v_link.hospital_id
           AND sh.shift_status='Active' AND sh.start_datetime<=now()
           AND sh.end_datetime>now())
       OR public.corvia_ops_eligibility(v_link.hospital_id,v_crew.unit_id,
                                      v_team.required_capability) IS NOT NULL
       OR NOT EXISTS (SELECT 1 FROM public.corvia_ws6_crew_members_actual cm
         WHERE cm.hospital_id=v_link.hospital_id AND cm.crew_id=p_crew_id AND cm.is_active)
       OR EXISTS (SELECT 1 FROM public.corvia_ws6_crew_members_actual cm
         JOIN public.corvia_ws6_ems_members m ON m.member_id=cm.member_id
         WHERE cm.hospital_id=v_link.hospital_id AND cm.crew_id=p_crew_id AND cm.is_active
           AND (NOT m.is_active OR m.verification_status<>'verified'
             OR m.verification_expiry_date IS NULL
             OR m.verification_expiry_date<(now() AT TIME ZONE 'Africa/Johannesburg')::date
             OR m.credential_verified_by IS NULL
             OR m.credential_verified_by=m.auth_user_id))
       OR EXISTS (SELECT 1 FROM public.corvia_ws6_incident_assignments_actual a
         WHERE a.hospital_id=v_link.hospital_id AND a.crew_id=p_crew_id AND a.is_active) THEN
      RAISE EXCEPTION 'Backup crew or vehicle is not currently eligible'
        USING ERRCODE='P0001';
    END IF;
    INSERT INTO ws4_private.ems_backups
      (ws4_incident_id,hospital_id,ems_incident_id,crew_id,unit_id,state,reason,offered_by)
      VALUES(p_ws4_incident_id,v_link.hospital_id,v_link.ems_incident_id,
        p_crew_id,v_crew.unit_id,'offered',p_reason,auth.uid()) RETURNING id INTO v_id;
    UPDATE public.corvia_ws6_units_actual SET status='Assigned',
      availability_revision=availability_revision+1
      WHERE hospital_id=v_link.hospital_id AND unit_id=v_crew.unit_id;
  ELSE
    SELECT * INTO v_backup FROM ws4_private.ems_backups
      WHERE ws4_incident_id=p_ws4_incident_id
        AND state IN ('offered','acknowledged','en_route','on_scene') FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'No active backup to release' USING ERRCODE='P0001'; END IF;
    v_id:=v_backup.id;
    UPDATE ws4_private.ems_backups SET state='released',version=version+1,
      released_at=now() WHERE id=v_id;
    PERFORM ws4_private.release_backup_unit(v_link.hospital_id,v_backup.unit_id);
  END IF;
  UPDATE public.corvia_ws6_incidents_actual SET revision=revision+1
    WHERE hospital_id=v_link.hospital_id AND incident_id=v_link.ems_incident_id;
  v_result:=jsonb_build_object('backup_id',v_id::text,'operation_id',p_operation_id,
    'state',CASE WHEN p_action='offer' THEN 'offered' ELSE 'released' END);
  INSERT INTO ws4_private.ems_backup_receipts
    (user_id,operation_id,backup_id,action,payload,result)
    VALUES(auth.uid(),p_operation_id,v_id,p_action,v_payload,v_result);
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,entity_id,new_value,reason)
    VALUES(v_link.hospital_id,auth.uid(),v_link.ems_incident_id,
      'backup_'||p_action,'backup',v_id,v_result,p_reason);
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_backup_crew(
  p_backup_id bigint,p_operation_id uuid,p_expected_version bigint,p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_backup ws4_private.ems_backups%ROWTYPE; v_old ws4_private.ems_backup_receipts%ROWTYPE;
  v_result jsonb; v_payload jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_operation_id IS NULL
     OR p_operation_id='00000000-0000-0000-0000-000000000000'
     OR p_expected_version IS NULL OR p_expected_version<1
     OR p_action IS NULL OR p_action NOT IN
       ('acknowledge','decline','en_route','on_scene') THEN
    RAISE EXCEPTION 'Valid backup response required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_backup FROM ws4_private.ems_backups WHERE id=p_backup_id;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM public.corvia_ws6_crew_members_actual cm
    JOIN public.corvia_ws6_crews c ON c.crew_id=cm.crew_id AND c.hospital_id=cm.hospital_id
      AND c.crew_status='Active' AND c.start_datetime<=now() AND c.end_datetime>now()
    JOIN public.corvia_ws6_shifts_actual sh ON sh.shift_id=c.shift_id
      AND sh.hospital_id=c.hospital_id AND sh.shift_status='Active'
      AND sh.start_datetime<=now() AND sh.end_datetime>now()
    WHERE cm.hospital_id=v_backup.hospital_id AND cm.crew_id=v_backup.crew_id
      AND cm.is_active AND cm.left_datetime IS NULL
      AND cm.member_id=public.corvia_ems_member(v_backup.hospital_id)) THEN
    RAISE EXCEPTION 'Current backup crew membership required' USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_backup.hospital_id::text,0));
  SELECT * INTO v_backup FROM ws4_private.ems_backups WHERE id=p_backup_id FOR UPDATE;
  v_payload:=jsonb_build_object('backup_id',p_backup_id::text,
    'version',p_expected_version::text,'action',p_action);
  SELECT * INTO v_old FROM ws4_private.ems_backup_receipts
    WHERE user_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_old.action<>p_action OR v_old.payload<>v_payload THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023';
    END IF;
    RETURN v_old.result;
  END IF;
  IF v_backup.version<>p_expected_version OR NOT (
    (v_backup.state='offered' AND p_action IN ('acknowledge','decline')) OR
    (v_backup.state='acknowledged' AND p_action='en_route') OR
    (v_backup.state='en_route' AND p_action='on_scene')) THEN
    RAISE EXCEPTION 'Backup offer changed' USING ERRCODE='P0001';
  END IF;
  UPDATE ws4_private.ems_backups
    SET state=CASE p_action WHEN 'acknowledge' THEN 'acknowledged'
      WHEN 'decline' THEN 'declined' ELSE p_action END,
        version=version+1,answered_at=now()
    WHERE id=p_backup_id;
  IF p_action='decline' THEN
    PERFORM ws4_private.release_backup_unit(v_backup.hospital_id,v_backup.unit_id);
  END IF;
  UPDATE public.corvia_ws6_incidents_actual
    SET revision=revision+1,dispatch_state=CASE WHEN p_action='decline'
      THEN 'escalated' ELSE dispatch_state END
    WHERE hospital_id=v_backup.hospital_id AND incident_id=v_backup.ems_incident_id;
  v_result:=jsonb_build_object('backup_id',p_backup_id::text,
    'operation_id',p_operation_id,'state',CASE p_action
      WHEN 'acknowledge' THEN 'acknowledged'
      WHEN 'decline' THEN 'declined' ELSE p_action END);
  INSERT INTO ws4_private.ems_backup_receipts
    (user_id,operation_id,backup_id,action,payload,result)
    VALUES(auth.uid(),p_operation_id,p_backup_id,p_action,v_payload,v_result);
  INSERT INTO public.corvia_ws6_audit_logs
    (hospital_id,actor_auth_user_id,incident_id,action_type,entity_type,entity_id,new_value)
    VALUES(v_backup.hospital_id,auth.uid(),v_backup.ems_incident_id,
      'backup_'||p_action,'backup',p_backup_id,v_result);
  RETURN v_result;
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_receiver_inbox(),
  public.corvia_ws4_team_case_mode(uuid,bigint),
  public.corvia_ws4_receiver_ack(bigint,uuid,text),
  public.corvia_ws4_backup_overview(bigint),
  public.corvia_ws4_backup_dispatch(bigint,uuid,bigint,text,bigint,text),
  public.corvia_ws4_backup_crew(bigint,uuid,bigint,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_receiver_inbox(),
  public.corvia_ws4_team_case_mode(uuid,bigint),
  public.corvia_ws4_receiver_ack(bigint,uuid,text),
  public.corvia_ws4_backup_overview(bigint),
  public.corvia_ws4_backup_dispatch(bigint,uuid,bigint,text,bigint,text),
  public.corvia_ws4_backup_crew(bigint,uuid,bigint,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
