-- Additive unit/crew response workflow. Owner-provisioned identities; no fixture data.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' OR to_regclass('ws4_dev_private.dispatch_commands') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4 operations and database owner required';
  END IF;
END $$;

CREATE TABLE ws4_dev_private.response_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  acknowledgement_seconds integer NOT NULL DEFAULT 120 CHECK(acknowledgement_seconds BETWEEN 30 AND 600),
  location_fresh_seconds integer NOT NULL DEFAULT 300 CHECK(location_fresh_seconds BETWEEN 30 AND 900)
);
INSERT INTO ws4_dev_private.response_settings DEFAULT VALUES;
CREATE TABLE ws4_dev_private.response_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  label text NOT NULL CHECK(char_length(label) BETWEEN 1 AND 80),
  ready boolean NOT NULL DEFAULT false,
  readiness_valid_until timestamptz,
  latitude double precision CHECK(latitude BETWEEN -90 AND 90),
  longitude double precision CHECK(longitude BETWEEN -180 AND 180),
  location_at timestamptz,
  accuracy_metres double precision CHECK(accuracy_metres>=0 AND accuracy_metres<100000),
  location_source text CHECK(location_source IN ('device','operator')),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  UNIQUE(id,organisation_id)
);
CREATE TABLE ws4_dev_private.response_crews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  unit_id uuid NOT NULL UNIQUE,
  label text NOT NULL CHECK(char_length(label) BETWEEN 1 AND 80),
  active boolean NOT NULL DEFAULT false,
  verified_until timestamptz NOT NULL,
  shift_start timestamptz NOT NULL,
  shift_end timestamptz NOT NULL CHECK(shift_end>shift_start),
  FOREIGN KEY(unit_id,organisation_id) REFERENCES ws4_dev_private.response_units(id,organisation_id),
  UNIQUE(id,organisation_id)
);
CREATE TABLE ws4_dev_private.response_crew_members (
  crew_id uuid NOT NULL REFERENCES ws4_dev_private.response_crews(id),
  user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(user_id),
  active boolean NOT NULL DEFAULT false,
  verified_until timestamptz NOT NULL,
  PRIMARY KEY(crew_id,user_id)
);
CREATE TABLE ws4_dev_private.response_destinations (
  hospital_id uuid PRIMARY KEY,
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  active boolean NOT NULL DEFAULT false
);
-- Existing public.hospitals is canonical. The synthetic bootstrap deliberately
-- does not create a second hospital directory; a test fixture may supply it.
DO $$ BEGIN
  IF to_regclass('public.hospitals') IS NOT NULL THEN
    ALTER TABLE ws4_dev_private.response_destinations ADD FOREIGN KEY(hospital_id) REFERENCES public.hospitals(id);
  END IF;
END $$;
CREATE TABLE ws4_dev_private.response_receivers (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  hospital_id uuid NOT NULL REFERENCES ws4_dev_private.response_destinations(hospital_id),
  active boolean NOT NULL DEFAULT false,
  PRIMARY KEY(user_id,hospital_id)
);
CREATE TABLE ws4_dev_private.response_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  unit_id uuid NOT NULL REFERENCES ws4_dev_private.response_units(id),
  crew_id uuid NOT NULL REFERENCES ws4_dev_private.response_crews(id),
  purpose text NOT NULL CHECK(purpose IN ('primary','backup')),
  state text NOT NULL DEFAULT 'offered' CHECK(state IN ('offered','acknowledged','en_route','on_scene','transporting','at_hospital','handover_requested','completed','rejected','withdrawn','timed_out')),
  active boolean NOT NULL DEFAULT true,
  acknowledgement_deadline timestamptz NOT NULL,
  destination_id uuid REFERENCES ws4_dev_private.response_destinations(hospital_id),
  attention text,
  patient_confirmed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(active=(state NOT IN ('completed','rejected','withdrawn','timed_out')))
);
CREATE UNIQUE INDEX response_unit_reserved ON ws4_dev_private.response_assignments(unit_id) WHERE active;
CREATE UNIQUE INDEX response_crew_reserved ON ws4_dev_private.response_assignments(crew_id) WHERE active;
CREATE UNIQUE INDEX response_incident_slot ON ws4_dev_private.response_assignments(incident_id,purpose) WHERE active;
CREATE TABLE ws4_dev_private.response_assignment_members (
  assignment_id uuid NOT NULL REFERENCES ws4_dev_private.response_assignments(id),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  PRIMARY KEY(assignment_id,user_id)
);
CREATE TABLE ws4_dev_private.response_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  assignment_id uuid REFERENCES ws4_dev_private.response_assignments(id),
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  actor_role text NOT NULL,
  command text NOT NULL,
  detail text NOT NULL CHECK(char_length(detail)<=1000),
  occurred_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL,
  UNIQUE(incident_id,version)
);
CREATE TABLE ws4_dev_private.response_operations (
  actor_id uuid NOT NULL, operation_id uuid NOT NULL,
  incident_id bigint NOT NULL, expected_version bigint NOT NULL,
  command text NOT NULL, payload jsonb NOT NULL, result jsonb NOT NULL,
  PRIMARY KEY(actor_id,operation_id)
);
CREATE TABLE ws4_dev_private.response_unit_operations (
  actor_id uuid NOT NULL REFERENCES auth.users(id), operation_id uuid NOT NULL,
  unit_id uuid NOT NULL REFERENCES ws4_dev_private.response_units(id), expected_version bigint NOT NULL,
  payload jsonb NOT NULL,result jsonb NOT NULL,recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,operation_id)
);
CREATE TABLE ws4_dev_private.response_fleet_reviewers (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  organisation_id uuid NOT NULL REFERENCES ws4_dev_private.organisations(id),
  active boolean NOT NULL DEFAULT false,
  PRIMARY KEY(user_id,organisation_id)
);
CREATE TABLE ws4_dev_private.response_readiness_reviews (
  actor_id uuid NOT NULL REFERENCES public.profiles(user_id),operation_id uuid NOT NULL,
  unit_id uuid NOT NULL REFERENCES ws4_dev_private.response_units(id),expected_version bigint NOT NULL,
  payload jsonb NOT NULL,result jsonb NOT NULL,approved boolean NOT NULL,
  valid_until timestamptz NOT NULL,recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,operation_id)
);
CREATE FUNCTION public.corvia_response_review_readiness(p_unit_id uuid,p_operation_id uuid,p_expected_version bigint,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE u ws4_dev_private.response_units%ROWTYPE; prior ws4_dev_private.response_readiness_reviews%ROWTYPE;
  k text; approved boolean:=true; expiry timestamptz; result jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(734004005);
  SELECT * INTO u FROM ws4_dev_private.response_units WHERE id=p_unit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM ws4_dev_private.response_fleet_reviewers r JOIN public.profiles p ON p.user_id=r.user_id
    WHERE r.user_id=auth.uid() AND r.organisation_id=u.organisation_id AND r.active AND p.is_active IS TRUE FOR SHARE OF r,p;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM ws4_dev_private.response_crews c JOIN ws4_dev_private.response_crew_members m ON m.crew_id=c.id WHERE c.unit_id=u.id AND m.user_id=auth.uid() AND m.active) THEN
    RAISE EXCEPTION 'Independent authorised fleet reviewer required' USING ERRCODE='42501'; END IF;
  SELECT * INTO prior FROM ws4_dev_private.response_readiness_reviews WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF prior.unit_id IS DISTINCT FROM p_unit_id OR prior.expected_version IS DISTINCT FROM p_expected_version OR prior.payload IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'Operation changed' USING ERRCODE='22023'; END IF;
    RETURN prior.result;
  END IF;
  IF u.version IS DISTINCT FROM p_expected_version OR EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE unit_id=u.id AND active) THEN RAISE EXCEPTION 'Refresh or release assignment before reviewing readiness' USING ERRCODE='P0001'; END IF;
  IF p_operation_id IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR nullif(btrim(p_payload->>'text'),'') IS NULL OR char_length(p_payload->>'text')>900 THEN RAISE EXCEPTION 'Review reason required' USING ERRCODE='22023'; END IF;
  FOREACH k IN ARRAY ARRAY['inspection','equipment','oxygen','fuel','communications','cleaning','documents','no_faults','capability'] LOOP
    IF jsonb_typeof(p_payload->k) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Complete all readiness checks' USING ERRCODE='22023'; END IF;
    approved:=approved AND (p_payload->>k)::boolean;
  END LOOP;
  expiry:=(p_payload->>'valid_until')::timestamptz;
  IF expiry IS NULL OR NOT isfinite(expiry) OR expiry<=now() OR expiry>now()+interval '12 hours' THEN RAISE EXCEPTION 'Readiness expiry must be within 12 hours' USING ERRCODE='22023'; END IF;
  UPDATE ws4_dev_private.response_units SET ready=approved,readiness_valid_until=expiry,version=version+1 WHERE id=u.id;
  result:=jsonb_build_object('unit_id',u.id,'operation_id',p_operation_id,'version',(u.version+1)::text);
  INSERT INTO ws4_dev_private.response_readiness_reviews VALUES(auth.uid(),p_operation_id,u.id,p_expected_version,p_payload,result,approved,expiry,now());
  RETURN result;
END $$;

CREATE FUNCTION public.corvia_response_my_unit() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE result jsonb;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE) THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',u.id,'label',u.label,'version',u.version::text,'location_at',u.location_at) INTO result
    FROM ws4_dev_private.response_units u JOIN ws4_dev_private.response_crews c ON c.unit_id=u.id
    JOIN ws4_dev_private.response_crew_members m ON m.crew_id=c.id
    WHERE m.user_id=auth.uid() AND m.active AND m.verified_until>now() AND c.active AND c.verified_until>now() AND now()>=c.shift_start AND now()<c.shift_end;
  RETURN jsonb_build_object('unit',result);
END $$;

CREATE FUNCTION public.corvia_response_unit_location(p_unit_id uuid,p_operation_id uuid,p_expected_version bigint,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE u ws4_dev_private.response_units%ROWTYPE; prior ws4_dev_private.response_unit_operations%ROWTYPE; occurred timestamptz; result jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(734004005);
  PERFORM 1 FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO u FROM ws4_dev_private.response_units WHERE id=p_unit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM ws4_dev_private.response_crews c JOIN ws4_dev_private.response_crew_members m ON m.crew_id=c.id
    WHERE c.unit_id=u.id AND m.user_id=auth.uid() AND m.active AND m.verified_until>now() AND c.active AND c.verified_until>now() AND now()>=c.shift_start AND now()<c.shift_end FOR SHARE OF c,m;
  IF NOT FOUND THEN RAISE EXCEPTION 'Current verified crew required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000' OR p_expected_version IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid location operation' USING ERRCODE='22023'; END IF;
  SELECT * INTO prior FROM ws4_dev_private.response_unit_operations WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (prior.unit_id,prior.expected_version,prior.payload) IS DISTINCT FROM(p_unit_id,p_expected_version,p_payload) THEN RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023'; END IF;
    RETURN prior.result;
  END IF;
  IF u.version<>p_expected_version THEN RAISE EXCEPTION 'Unit changed; refresh' USING ERRCODE='P0001'; END IF;
  occurred:=(p_payload->>'occurred_at')::timestamptz;
  IF occurred IS NULL OR NOT isfinite(occurred) OR occurred<now()-interval '120 seconds' OR occurred>now()+interval '5 seconds' OR
    (u.location_at IS NOT NULL AND occurred<u.location_at) OR p_payload->>'latitude' IS NULL OR p_payload->>'longitude' IS NULL OR p_payload->>'accuracy_metres' IS NULL OR
    NOT ((p_payload->>'latitude')::double precision BETWEEN -90 AND 90) OR NOT ((p_payload->>'longitude')::double precision BETWEEN -180 AND 180) OR
    NOT ((p_payload->>'accuracy_metres')::double precision>=0 AND (p_payload->>'accuracy_metres')::double precision<100000) THEN RAISE EXCEPTION 'Fresh ordered device location required' USING ERRCODE='22023'; END IF;
  UPDATE ws4_dev_private.response_units SET latitude=(p_payload->>'latitude')::double precision,longitude=(p_payload->>'longitude')::double precision,
    accuracy_metres=(p_payload->>'accuracy_metres')::double precision,location_at=occurred,location_source='device',version=version+1 WHERE id=u.id RETURNING * INTO u;
  result:=jsonb_build_object('unit_id',u.id,'operation_id',p_operation_id,'version',u.version::text);
  INSERT INTO ws4_dev_private.response_unit_operations(actor_id,operation_id,unit_id,expected_version,payload,result) VALUES(auth.uid(),p_operation_id,u.id,p_expected_version,p_payload,result);
  RETURN result;
END $$;

CREATE FUNCTION ws4_dev_private.response_destination_active(p_hospital uuid,p_organisation uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE found_id uuid;
BEGIN
  IF to_regclass('public.hospitals') IS NULL THEN RETURN false; END IF;
  EXECUTE 'SELECT h.id FROM public.hospitals h JOIN ws4_dev_private.response_destinations d ON d.hospital_id=h.id WHERE h.id=$1 AND d.organisation_id=$2 AND d.active AND h.is_active IS TRUE FOR SHARE OF h,d' INTO found_id USING p_hospital,p_organisation;
  RETURN found_id IS NOT NULL;
END $$;

CREATE FUNCTION ws4_dev_private.response_role(p_incident_id bigint) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i public.incidents%ROWTYPE; r text;
BEGIN
  PERFORM 1 FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO i FROM public.incidents WHERE id=p_incident_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT role INTO r FROM ws4_dev_private.memberships WHERE user_id=auth.uid() AND organisation_id=i.organisation_id AND active FOR SHARE;
  IF FOUND THEN RETURN r; END IF;
  PERFORM 1 FROM ws4_dev_private.response_crew_members m
    JOIN ws4_dev_private.response_crews c ON c.id=m.crew_id
    JOIN ws4_dev_private.response_assignments a ON a.crew_id=c.id
    WHERE m.user_id=auth.uid() AND m.active AND m.verified_until>now() AND c.active AND c.verified_until>now()
      AND now()>=c.shift_start AND now()<c.shift_end AND c.organisation_id=i.organisation_id
      AND a.incident_id=i.id AND a.active AND EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members am WHERE am.assignment_id=a.id AND am.user_id=auth.uid()) FOR SHARE OF m,c;
  IF FOUND THEN RETURN 'crew'; END IF;
  PERFORM 1 FROM ws4_dev_private.response_receivers r
    JOIN ws4_dev_private.response_destinations d ON d.hospital_id=r.hospital_id
    JOIN ws4_dev_private.response_assignments a ON a.destination_id=d.hospital_id
    WHERE r.user_id=auth.uid() AND r.active AND d.active AND d.organisation_id=i.organisation_id
      AND a.incident_id=i.id AND a.active FOR SHARE OF r,d;
  IF FOUND THEN RETURN 'receiver'; END IF;
  RAISE EXCEPTION 'Access denied' USING ERRCODE='42501';
END $$;

CREATE FUNCTION ws4_dev_private.response_unit_reason(p_unit_id uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u ws4_dev_private.response_units%ROWTYPE; c ws4_dev_private.response_crews%ROWTYPE; ttl integer;
BEGIN
  SELECT * INTO u FROM ws4_dev_private.response_units WHERE id=p_unit_id FOR SHARE;
  IF NOT FOUND THEN RETURN 'Unit unavailable'; END IF;
  IF EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE unit_id=u.id AND active) THEN RETURN 'Already reserved'; END IF;
  IF NOT u.ready OR u.readiness_valid_until IS NULL OR u.readiness_valid_until<=now() THEN RETURN 'Readiness missing or expired'; END IF;
  IF NOT coalesce((SELECT approved AND valid_until>now() FROM ws4_dev_private.response_readiness_reviews WHERE unit_id=u.id ORDER BY recorded_at DESC LIMIT 1),false) THEN RETURN 'Recorded readiness review required'; END IF;
  SELECT location_fresh_seconds INTO ttl FROM ws4_dev_private.response_settings WHERE singleton;
  IF u.latitude IS NULL OR u.longitude IS NULL OR u.location_at IS NULL OR u.location_at>now() OR u.location_at<now()-make_interval(secs=>ttl) OR u.location_source IS NULL THEN RETURN 'Location missing or stale'; END IF;
  SELECT * INTO c FROM ws4_dev_private.response_crews WHERE unit_id=u.id FOR SHARE;
  IF NOT FOUND OR NOT c.active OR c.verified_until<=now() OR now()<c.shift_start OR now()>=c.shift_end THEN RETURN 'Verified on-shift crew required'; END IF;
  PERFORM 1 FROM ws4_dev_private.response_crew_members m JOIN public.profiles p ON p.user_id=m.user_id
    WHERE m.crew_id=c.id FOR SHARE OF m,p;
  IF NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_crew_members WHERE crew_id=c.id AND active)
    OR EXISTS(SELECT 1 FROM ws4_dev_private.response_crew_members m JOIN public.profiles p ON p.user_id=m.user_id
      WHERE m.crew_id=c.id AND m.active AND (m.verified_until<=now() OR p.is_active IS NOT TRUE)) THEN RETURN 'Crew verification missing or expired'; END IF;
  RETURN 'Eligible';
END $$;

CREATE FUNCTION ws4_dev_private.response_crew_available(p_assignment_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments a JOIN ws4_dev_private.response_crews c ON c.id=a.crew_id
    WHERE a.id=p_assignment_id AND c.active AND c.verified_until>now() AND now()>=c.shift_start AND now()<c.shift_end
      AND EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members am WHERE am.assignment_id=a.id)
      AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members am
        LEFT JOIN ws4_dev_private.response_crew_members m ON m.crew_id=c.id AND m.user_id=am.user_id
        LEFT JOIN public.profiles p ON p.user_id=am.user_id
        WHERE am.assignment_id=a.id AND (m.active IS NOT TRUE OR m.verified_until<=now() OR p.is_active IS NOT TRUE)));
$$;

CREATE FUNCTION public.corvia_response_inbox(p_include_closed boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids jsonb;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE) THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  IF NOT public.corvia_is_dispatch_operator() AND NOT EXISTS(
    SELECT 1 FROM ws4_dev_private.response_crew_members m JOIN ws4_dev_private.response_crews c ON c.id=m.crew_id
    WHERE m.user_id=auth.uid() AND m.active AND m.verified_until>now() AND c.active AND c.verified_until>now() AND now()>=c.shift_start AND now()<c.shift_end)
    AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_receivers r JOIN ws4_dev_private.response_destinations d ON d.hospital_id=r.hospital_id WHERE r.user_id=auth.uid() AND r.active AND d.active) THEN
    RAISE EXCEPTION 'Active response membership required' USING ERRCODE='42501'; END IF;
  SELECT coalesce(jsonb_agg(id::text ORDER BY id DESC),'[]'::jsonb) INTO ids FROM (
    SELECT DISTINCT i.id FROM public.incidents i WHERE (i.status='in_progress' OR (p_include_closed IS TRUE AND i.status IN ('resolved','cancelled') AND ws4_dev_private.in_scope(i.organisation_id))) AND (
      ws4_dev_private.in_scope(i.organisation_id) OR EXISTS(
        SELECT 1 FROM ws4_dev_private.response_assignments a JOIN ws4_dev_private.response_crews c ON c.id=a.crew_id
        JOIN ws4_dev_private.response_crew_members m ON m.crew_id=c.id
        WHERE a.incident_id=i.id AND a.active AND m.user_id=auth.uid() AND m.active AND m.verified_until>now()
          AND EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members am WHERE am.assignment_id=a.id AND am.user_id=auth.uid())
          AND c.organisation_id=i.organisation_id AND c.active AND c.verified_until>now() AND now()>=c.shift_start AND now()<c.shift_end) OR EXISTS(
        SELECT 1 FROM ws4_dev_private.response_assignments a JOIN ws4_dev_private.response_receivers r ON r.hospital_id=a.destination_id
        JOIN ws4_dev_private.response_destinations d ON d.hospital_id=r.hospital_id
        WHERE a.incident_id=i.id AND a.active AND r.user_id=auth.uid() AND r.active AND d.active AND d.organisation_id=i.organisation_id))
    ORDER BY i.id DESC LIMIT 101) q;
  IF jsonb_array_length(ids)>100 THEN RAISE EXCEPTION 'Inbox exceeds supported bound; contact dispatch' USING ERRCODE='P0001'; END IF;
  RETURN jsonb_build_object('incidents',ids,'server_time',now());
END $$;

CREATE FUNCTION public.corvia_response_workspace(p_incident_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE r text; i public.incidents%ROWTYPE; units jsonb; assignments jsonb; events jsonb; destinations jsonb:='[]';
BEGIN
  PERFORM pg_advisory_xact_lock(734004005);
  r:=ws4_dev_private.response_role(p_incident_id);
  SELECT * INTO i FROM public.incidents WHERE id=p_incident_id;
  IF (SELECT count(*) FROM ws4_dev_private.response_assignments WHERE incident_id=i.id)>200
     OR (SELECT count(*) FROM ws4_dev_private.response_units WHERE organisation_id=i.organisation_id)>200 THEN
    RAISE EXCEPTION 'Response workspace exceeds supported bound' USING ERRCODE='P0001'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'unit_id',a.unit_id,'unit',u.label,'crew',c.label,'state',a.state,'active',a.active,
    'purpose',a.purpose,'deadline',a.acknowledgement_deadline,'overdue',a.state='offered' AND a.acknowledgement_deadline<=now(),
    'destination_id',a.destination_id,'attention',a.attention,'patient_confirmed',a.patient_confirmed,'crew_available',ws4_dev_private.response_crew_available(a.id),
    'mine',EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members m WHERE m.assignment_id=a.id AND m.user_id=auth.uid()),
    'latitude',u.latitude,'longitude',u.longitude,'location_at',u.location_at,'location_source',u.location_source,'accuracy_metres',u.accuracy_metres,
    'location_fresh',(u.latitude IS NOT NULL AND u.longitude IS NOT NULL AND u.location_at<=now() AND u.location_at>=now()-make_interval(secs=>(SELECT location_fresh_seconds FROM ws4_dev_private.response_settings WHERE singleton))) IS TRUE)
    ORDER BY a.created_at,a.id),'[]'::jsonb) INTO assignments
    FROM ws4_dev_private.response_assignments a JOIN ws4_dev_private.response_units u ON u.id=a.unit_id JOIN ws4_dev_private.response_crews c ON c.id=a.crew_id WHERE a.incident_id=i.id;
  IF r IN ('dispatcher','dispatch_supervisor') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'label',u.label,'version',u.version::text,'reason',ws4_dev_private.response_unit_reason(u.id),
      'can_review',EXISTS(SELECT 1 FROM ws4_dev_private.response_fleet_reviewers f WHERE f.user_id=auth.uid() AND f.organisation_id=u.organisation_id AND f.active),
      'review',(SELECT jsonb_build_object('actor',v.actor_id,'recorded_at',v.recorded_at,'valid_until',v.valid_until,'approved',v.approved,'reason',v.payload->>'text') FROM ws4_dev_private.response_readiness_reviews v WHERE v.unit_id=u.id ORDER BY v.recorded_at DESC LIMIT 1)) ORDER BY u.label,u.id),'[]'::jsonb)
      INTO units FROM ws4_dev_private.response_units u WHERE u.organisation_id=i.organisation_id;
  END IF;
  IF to_regclass('public.hospitals') IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(jsonb_agg(jsonb_build_object(''id'',h.id,''label'',h.name,''latitude'',h.latitude,''longitude'',h.longitude,''phone'',to_jsonb(h)->>''phone'',''address'',to_jsonb(h)->>''address'',''directory_updated_at'',to_jsonb(h)->>''updated_at'') ORDER BY h.name),''[]''::jsonb) FROM public.hospitals h JOIN ws4_dev_private.response_destinations d ON d.hospital_id=h.id WHERE d.organisation_id=$1 AND d.active AND h.is_active IS TRUE' INTO destinations USING i.organisation_id;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.version::bigint DESC),'[]'::jsonb) INTO events FROM (
    SELECT id::text,assignment_id,actor_id,actor_role,command,detail,occurred_at,recorded_at,version::text FROM (
      SELECT id,assignment_id,actor_id,actor_role,command,detail,occurred_at,recorded_at,version
        FROM ws4_dev_private.response_events WHERE incident_id=i.id
      UNION ALL
      SELECT version,NULL::uuid,actor_user_id,'incident',event_type,concat_ws(' -> ',previous_status,status),recorded_at,recorded_at,version
        FROM ws4_dev_private.incident_events e WHERE incident_id=i.id AND NOT EXISTS(
          SELECT 1 FROM ws4_dev_private.response_events r WHERE r.incident_id=e.incident_id AND r.version=e.version)
    ) combined ORDER BY combined.version DESC LIMIT 100) e;
  RETURN jsonb_build_object('incident_id',i.id::text,'version',i.version::text,'role',r,'can_manage',(r='dispatch_supervisor' OR (r='dispatcher' AND i.assigned_dispatcher_user_id=auth.uid())) IS TRUE,
    'status',i.status,'server_time',now(),'latitude',i.latitude,'longitude',i.longitude,
    'scene_details',i.details,'priority',coalesce((SELECT priority FROM ws4_dev_private.incident_workspace WHERE incident_id=i.id),'untriaged'),
    'location_source',i.location_source,'location_at',i.location_captured_at,'accuracy_metres',i.location_accuracy,'address',i.address,
    'units',coalesce(units,'[]'),'assignments',assignments,'destinations',destinations,'events',events,
    'older_events', (SELECT count(*)>100 FROM ws4_dev_private.incident_events WHERE incident_id=i.id));
END $$;

CREATE FUNCTION public.corvia_response_command(p_incident_id bigint,p_operation_id uuid,p_expected_version bigint,p_command text,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE r text; i public.incidents%ROWTYPE; a ws4_dev_private.response_assignments%ROWTYPE;
  prior ws4_dev_private.response_operations%ROWTYPE; u ws4_dev_private.response_units%ROWTYPE; c ws4_dev_private.response_crews%ROWTYPE;
  assignment uuid; detail text; occurred timestamptz; result jsonb; next_state text; is_manager boolean; seconds integer;
BEGIN
  PERFORM pg_advisory_xact_lock(734004005);
  r:=ws4_dev_private.response_role(p_incident_id);
  SELECT * INTO i FROM public.incidents WHERE id=p_incident_id;
  is_manager:=(r='dispatch_supervisor' OR (r='dispatcher' AND i.assigned_dispatcher_user_id=auth.uid())) IS TRUE;
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000' OR p_expected_version IS NULL OR p_expected_version<1 OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR p_command IS NULL THEN
    RAISE EXCEPTION 'Invalid command' USING ERRCODE='22023'; END IF;
  SELECT * INTO prior FROM ws4_dev_private.response_operations WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (prior.incident_id,prior.expected_version,prior.command,prior.payload) IS DISTINCT FROM (p_incident_id,p_expected_version,p_command,p_payload) THEN RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023'; END IF;
    RETURN prior.result;
  END IF;
  IF i.status<>'in_progress' OR i.version<>p_expected_version THEN RAISE EXCEPTION 'Incident changed; refresh' USING ERRCODE='P0001'; END IF;
  detail:=btrim(coalesce(p_payload->>'text',''));
  IF char_length(detail)>1000 THEN RAISE EXCEPTION 'Text too long' USING ERRCODE='22023'; END IF;
  occurred:=coalesce((p_payload->>'occurred_at')::timestamptz,now());
  IF NOT isfinite(occurred) OR occurred>now()+interval '5 seconds' OR occurred<i.created_at THEN RAISE EXCEPTION 'Invalid event time' USING ERRCODE='22023'; END IF;
  IF p_command='assign' THEN
    IF NOT is_manager THEN RAISE EXCEPTION 'Dispatch owner required' USING ERRCODE='42501'; END IF;
    IF EXISTS(SELECT 1 FROM ws4_dev_private.incident_workspace WHERE incident_id=i.id AND provider_state IN ('accepted','unknown')) THEN RAISE EXCEPTION 'Reconcile provider before internal allocation' USING ERRCODE='P0001'; END IF;
    SELECT * INTO u FROM ws4_dev_private.response_units WHERE id=(p_payload->>'unit_id')::uuid AND organisation_id=i.organisation_id FOR UPDATE;
    IF NOT FOUND OR u.version::text IS DISTINCT FROM p_payload->>'unit_version' OR ws4_dev_private.response_unit_reason(u.id)<>'Eligible' THEN RAISE EXCEPTION 'Unit is no longer eligible' USING ERRCODE='P0001'; END IF;
    IF p_payload->>'purpose' NOT IN ('primary','backup') OR p_payload->>'purpose' IS NULL THEN RAISE EXCEPTION 'Invalid assignment purpose' USING ERRCODE='22023'; END IF;
    IF p_payload->>'purpose'='backup' AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE incident_id=i.id AND active AND attention='backup') THEN RAISE EXCEPTION 'Backup request required' USING ERRCODE='P0001'; END IF;
    SELECT * INTO c FROM ws4_dev_private.response_crews WHERE unit_id=u.id;
    SELECT acknowledgement_seconds INTO seconds FROM ws4_dev_private.response_settings WHERE singleton;
    INSERT INTO ws4_dev_private.response_assignments(incident_id,unit_id,crew_id,purpose,acknowledgement_deadline)
      VALUES(i.id,u.id,c.id,p_payload->>'purpose',now()+make_interval(secs=>seconds)) RETURNING id INTO assignment;
    INSERT INTO ws4_dev_private.response_assignment_members SELECT assignment,m.user_id FROM ws4_dev_private.response_crew_members m WHERE m.crew_id=c.id AND m.active;
  ELSE
    assignment:=(p_payload->>'assignment_id')::uuid;
    SELECT * INTO a FROM ws4_dev_private.response_assignments WHERE id=assignment AND incident_id=i.id AND active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment changed; refresh' USING ERRCODE='P0001'; END IF;
    IF occurred<a.created_at THEN RAISE EXCEPTION 'Event predates assignment' USING ERRCODE='22023'; END IF;
    IF r='crew' AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_assignment_members WHERE assignment_id=a.id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Assigned crew required' USING ERRCODE='42501'; END IF;
    IF r='receiver' AND NOT EXISTS(SELECT 1 FROM ws4_dev_private.response_receivers WHERE hospital_id=a.destination_id AND user_id=auth.uid() AND active) THEN RAISE EXCEPTION 'Receiving hospital required' USING ERRCODE='42501'; END IF;
    IF r='crew' AND p_command IN ('acknowledge','progress') THEN
      PERFORM 1 FROM public.profiles p JOIN ws4_dev_private.response_assignment_members m ON m.user_id=p.user_id WHERE m.assignment_id=a.id FOR SHARE OF p;
      IF NOT ws4_dev_private.response_crew_available(a.id) THEN RAISE EXCEPTION 'Crew eligibility changed; contact dispatch' USING ERRCODE='P0001'; END IF;
    END IF;
    CASE p_command
    WHEN 'acknowledge','reject' THEN
      IF r<>'crew' THEN RAISE EXCEPTION 'Crew required' USING ERRCODE='42501'; END IF;
      IF a.state<>'offered' OR a.acknowledgement_deadline<=now() THEN RAISE EXCEPTION 'Offer expired or changed' USING ERRCODE='P0001'; END IF;
      IF p_command='reject' AND detail='' THEN RAISE EXCEPTION 'Reason required' USING ERRCODE='22023'; END IF;
      next_state:=CASE WHEN p_command='acknowledge' THEN 'acknowledged' ELSE 'rejected' END;
    WHEN 'expire' THEN
      IF NOT is_manager THEN RAISE EXCEPTION 'Dispatch owner required' USING ERRCODE='42501'; END IF;
      IF a.state<>'offered' OR a.acknowledgement_deadline>now() THEN RAISE EXCEPTION 'Offer not expired' USING ERRCODE='P0001'; END IF;
      next_state:='timed_out';
    WHEN 'withdraw' THEN
      IF NOT is_manager OR (a.state<>'offered' AND r<>'dispatch_supervisor') THEN RAISE EXCEPTION 'Supervisor required after acknowledgement' USING ERRCODE='42501'; END IF;
      IF detail='' THEN RAISE EXCEPTION 'Reason required' USING ERRCODE='22023'; END IF;
      next_state:='withdrawn';
    WHEN 'progress' THEN
      IF r<>'crew' THEN RAISE EXCEPTION 'Crew required' USING ERRCODE='42501'; END IF;
      next_state:=p_payload->>'state';
      IF EXISTS(SELECT 1 FROM ws4_dev_private.response_events WHERE assignment_id=a.id AND command IN ('acknowledge','progress') AND occurred_at>occurred) THEN RAISE EXCEPTION 'Out-of-order progress requires review' USING ERRCODE='P0001'; END IF;
      IF next_state IS NULL OR a.attention IS NOT NULL OR NOT ((a.state='acknowledged' AND next_state='en_route') OR (a.state='en_route' AND next_state='on_scene') OR (a.state='on_scene' AND next_state='transporting') OR (a.state='transporting' AND next_state='at_hospital') OR (a.state='at_hospital' AND next_state='handover_requested')) THEN RAISE EXCEPTION 'Invalid progress transition or unresolved exception' USING ERRCODE='P0001'; END IF;
      IF next_state IN ('transporting','handover_requested') AND a.destination_id IS NULL THEN RAISE EXCEPTION 'Destination required' USING ERRCODE='P0001'; END IF;
      IF next_state='transporting' AND NOT a.patient_confirmed THEN RAISE EXCEPTION 'Crew patient-match confirmation required' USING ERRCODE='P0001'; END IF;
      IF next_state='handover_requested' AND detail='' THEN RAISE EXCEPTION 'Handover summary required' USING ERRCODE='22023'; END IF;
    WHEN 'confirm_patient' THEN
      IF r<>'crew' THEN RAISE EXCEPTION 'Assigned crew required' USING ERRCODE='42501'; END IF;
      IF a.state<>'on_scene' OR a.attention IS NOT NULL OR detail='' THEN RAISE EXCEPTION 'On-scene patient-match evidence required' USING ERRCODE='P0001'; END IF;
      UPDATE ws4_dev_private.response_assignments SET patient_confirmed=true WHERE id=a.id;
    WHEN 'destination' THEN
      IF NOT is_manager AND r<>'crew' THEN RAISE EXCEPTION 'Dispatch or crew required' USING ERRCODE='42501'; END IF;
      IF a.state IN ('at_hospital','handover_requested') AND (r<>'dispatch_supervisor' OR a.attention IS DISTINCT FROM 'handover_failed') THEN RAISE EXCEPTION 'Supervisor review of failed handover required before rerouting' USING ERRCODE='P0001'; END IF;
      PERFORM 1 FROM ws4_dev_private.response_destinations WHERE hospital_id=(p_payload->>'hospital_id')::uuid AND organisation_id=i.organisation_id AND active FOR SHARE;
      IF NOT FOUND OR detail='' OR NOT ws4_dev_private.response_destination_active((p_payload->>'hospital_id')::uuid,i.organisation_id) THEN RAISE EXCEPTION 'Verified destination and reason required' USING ERRCODE='22023'; END IF;
      UPDATE ws4_dev_private.response_assignments SET destination_id=(p_payload->>'hospital_id')::uuid WHERE id=a.id;
      IF a.state IN ('at_hospital','handover_requested') THEN
        UPDATE ws4_dev_private.response_assignments SET state='transporting',attention=NULL WHERE id=a.id;
      END IF;
    WHEN 'location' THEN
      IF r<>'crew' THEN RAISE EXCEPTION 'Assigned crew required' USING ERRCODE='42501'; END IF;
      IF EXISTS(SELECT 1 FROM ws4_dev_private.response_units WHERE id=a.unit_id AND location_at>occurred) THEN RAISE EXCEPTION 'Older location cannot replace newer position' USING ERRCODE='P0001'; END IF;
      IF p_payload->>'latitude' IS NULL OR p_payload->>'longitude' IS NULL OR p_payload->>'accuracy_metres' IS NULL OR
         NOT ((p_payload->>'latitude')::double precision BETWEEN -90 AND 90) OR NOT ((p_payload->>'longitude')::double precision BETWEEN -180 AND 180) OR
         NOT ((p_payload->>'accuracy_metres')::double precision>=0 AND (p_payload->>'accuracy_metres')::double precision<100000) OR
         occurred<now()-interval '120 seconds' THEN RAISE EXCEPTION 'Fresh device location required' USING ERRCODE='22023'; END IF;
      UPDATE ws4_dev_private.response_units SET latitude=(p_payload->>'latitude')::double precision,longitude=(p_payload->>'longitude')::double precision,
        accuracy_metres=(p_payload->>'accuracy_metres')::double precision,location_at=occurred,location_source='device',version=version+1 WHERE id=a.unit_id;
    WHEN 'handover_accept' THEN
      IF r<>'receiver' THEN RAISE EXCEPTION 'Independent receiving user required' USING ERRCODE='42501'; END IF;
      IF a.state<>'handover_requested' OR a.attention IS NOT NULL OR detail='' OR NOT ws4_dev_private.response_destination_active(a.destination_id,i.organisation_id) THEN RAISE EXCEPTION 'Handover request and receiver confirmation required' USING ERRCODE='P0001'; END IF;
      next_state:='completed';
    WHEN 'exception' THEN
      IF NOT is_manager AND r<>'crew' THEN RAISE EXCEPTION 'Dispatch or crew required' USING ERRCODE='42501'; END IF;
      IF p_payload->>'reason' NOT IN ('no_patient','unsafe_scene','multiple_patients','refusal','unit_failure','backup','handover_failed') OR p_payload->>'reason' IS NULL OR detail='' THEN RAISE EXCEPTION 'Exception and reason required' USING ERRCODE='22023'; END IF;
      IF a.attention IS NOT NULL AND a.attention IS DISTINCT FROM p_payload->>'reason' THEN RAISE EXCEPTION 'Review the existing exception before changing its type' USING ERRCODE='P0001'; END IF;
      UPDATE ws4_dev_private.response_assignments SET attention=p_payload->>'reason' WHERE id=a.id;
      IF p_payload->>'reason'='unit_failure' THEN UPDATE ws4_dev_private.response_units SET ready=false,version=version+1 WHERE id=a.unit_id; END IF;
      detail:=(p_payload->>'reason')||': '||detail;
    WHEN 'resolve_exception' THEN
      IF r<>'dispatch_supervisor' THEN RAISE EXCEPTION 'Supervisor required' USING ERRCODE='42501'; END IF;
      IF a.attention IS NULL OR detail='' THEN RAISE EXCEPTION 'Open exception and reason required' USING ERRCODE='22023'; END IF;
      IF a.attention='unit_failure' THEN RAISE EXCEPTION 'Withdraw failed unit and assign replacement' USING ERRCODE='P0001'; END IF;
      UPDATE ws4_dev_private.response_assignments SET attention=NULL WHERE id=a.id;
    WHEN 'message' THEN
      IF NOT is_manager AND r NOT IN ('crew','receiver') THEN RAISE EXCEPTION 'Participant required' USING ERRCODE='42501'; END IF;
      IF detail='' THEN RAISE EXCEPTION 'Message required' USING ERRCODE='22023'; END IF;
    ELSE RAISE EXCEPTION 'Unsupported response command' USING ERRCODE='22023';
    END CASE;
    IF next_state IS NOT NULL THEN
      UPDATE ws4_dev_private.response_assignments SET state=next_state,active=next_state NOT IN ('completed','rejected','withdrawn','timed_out') WHERE id=a.id;
      IF next_state='completed' OR (next_state='withdrawn' AND a.state<>'offered') THEN UPDATE ws4_dev_private.response_units SET ready=false,version=version+1 WHERE id=a.unit_id; END IF;
    END IF;
  END IF;
  IF char_length(detail)>1000 THEN RAISE EXCEPTION 'Event detail too long' USING ERRCODE='22023'; END IF;
  UPDATE public.incidents SET version=version+1 WHERE id=i.id RETURNING * INTO i;
  INSERT INTO ws4_dev_private.response_events(incident_id,assignment_id,actor_id,actor_role,command,detail,occurred_at,version)
    VALUES(i.id,assignment,auth.uid(),r,p_command,detail,occurred,i.version);
  result:=jsonb_build_object('incident_id',i.id::text,'operation_id',p_operation_id,'version',i.version::text,'assignment_id',assignment);
  INSERT INTO ws4_dev_private.response_operations VALUES(auth.uid(),p_operation_id,i.id,p_expected_version,p_command,p_payload,result);
  RETURN result;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Resource or assignment already reserved; refresh' USING ERRCODE='P0001';
END $$;

-- Existing closure and provider commands cannot bypass an active response.
CREATE FUNCTION ws4_dev_private.guard_response_closure() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.status IN ('resolved','cancelled') AND EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE incident_id=NEW.id AND active) THEN
    RAISE EXCEPTION 'Active crew response must be released or handed over first' USING ERRCODE='P0001'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER response_closure_guard BEFORE UPDATE ON public.incidents FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_response_closure();
CREATE FUNCTION ws4_dev_private.guard_response_provider() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.provider_state IN ('accepted','unknown') AND EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE incident_id=NEW.incident_id AND active) THEN
    RAISE EXCEPTION 'Internal crew response already active' USING ERRCODE='P0001'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER response_provider_guard BEFORE INSERT OR UPDATE ON ws4_dev_private.incident_workspace FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_response_provider();

-- A roster cannot silently change underneath a reserved assignment. Provision or
-- alter an idle crew, then explicitly review unit readiness again.
CREATE FUNCTION ws4_dev_private.guard_response_roster() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE crew uuid; unit uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(734004005);
  IF TG_TABLE_NAME='response_crews' THEN
    crew:=CASE WHEN TG_OP='DELETE' THEN OLD.id ELSE NEW.id END;
    unit:=CASE WHEN TG_OP='DELETE' THEN OLD.unit_id ELSE NEW.unit_id END;
    IF TG_OP='UPDATE' AND (NEW.id,NEW.unit_id,NEW.organisation_id) IS DISTINCT FROM (OLD.id,OLD.unit_id,OLD.organisation_id) THEN RAISE EXCEPTION 'Crew identity is immutable' USING ERRCODE='22023'; END IF;
  ELSE
    crew:=CASE WHEN TG_OP='DELETE' THEN OLD.crew_id ELSE NEW.crew_id END;
    IF TG_OP='UPDATE' AND (NEW.crew_id,NEW.user_id) IS DISTINCT FROM (OLD.crew_id,OLD.user_id) THEN RAISE EXCEPTION 'Membership identity is immutable' USING ERRCODE='22023'; END IF;
    SELECT unit_id INTO unit FROM ws4_dev_private.response_crews WHERE id=crew;
  END IF;
  IF EXISTS(SELECT 1 FROM ws4_dev_private.response_assignments WHERE crew_id=crew AND active) THEN RAISE EXCEPTION 'Release active assignment before changing roster; revoke profile for immediate access denial' USING ERRCODE='P0001'; END IF;
  UPDATE ws4_dev_private.response_units SET ready=false,version=version+1 WHERE id=unit;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER response_crew_guard BEFORE INSERT OR UPDATE OR DELETE ON ws4_dev_private.response_crews FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_response_roster();
CREATE TRIGGER response_member_guard BEFORE INSERT OR UPDATE OR DELETE ON ws4_dev_private.response_crew_members FOR EACH ROW EXECUTE FUNCTION ws4_dev_private.guard_response_roster();

DO $$ DECLARE t text; f record; BEGIN
  FOREACH t IN ARRAY ARRAY['response_settings','response_units','response_crews','response_crew_members','response_destinations','response_receivers','response_assignments','response_assignment_members','response_events','response_operations','response_unit_operations','response_fleet_reviewers','response_readiness_reviews'] LOOP
    EXECUTE format('ALTER TABLE ws4_dev_private.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON ws4_dev_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
  END LOOP;
  REVOKE ALL ON SEQUENCE ws4_dev_private.response_events_id_seq FROM PUBLIC,anon,authenticated,service_role;
  FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.nspname='ws4_dev_private' AND p.proname IN ('response_role','response_unit_reason','response_crew_available','response_destination_active','guard_response_closure','guard_response_provider','guard_response_roster')) OR
      (n.nspname='public' AND p.proname IN ('corvia_response_inbox','corvia_response_workspace','corvia_response_command','corvia_response_my_unit','corvia_response_unit_location','corvia_response_review_readiness')) LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.corvia_response_inbox(boolean),public.corvia_response_workspace(bigint),public.corvia_response_command(bigint,uuid,bigint,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_response_my_unit(),public.corvia_response_unit_location(uuid,uuid,bigint,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_response_review_readiness(uuid,uuid,bigint,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
