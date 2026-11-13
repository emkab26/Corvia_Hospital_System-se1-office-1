-- Incident-scoped WebRTC signalling. Owner review after 001; no legacy call
-- table is used. This stores signalling only and never changes incident status.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $$ BEGIN
  IF current_user <> 'postgres'
     OR to_regclass('ws4_private.memberships') IS NULL
     OR to_regclass('public.incidents') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4 core must be installed first';
  END IF;
  IF to_regclass('ws4_private.voice_sessions') IS NOT NULL THEN
    RAISE EXCEPTION 'Voice signalling already installed; inspect before changing it';
  END IF;
END $$;

CREATE TABLE ws4_private.voice_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  caller_id uuid NOT NULL REFERENCES auth.users(id),
  start_operation_id uuid NOT NULL,
  responder_id uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'ringing'
    CHECK (status IN ('ringing','answered','ended','timed_out')),
  offer_sdp text NOT NULL CHECK (octet_length(offer_sdp) BETWEEN 1 AND 100000),
  answer_sdp text CHECK (answer_sdp IS NULL OR
    octet_length(answer_sdp) BETWEEN 1 AND 100000),
  created_at timestamptz NOT NULL DEFAULT now(),
  answered_at timestamptz,
  ended_at timestamptz,
  UNIQUE(caller_id,start_operation_id)
);
CREATE UNIQUE INDEX ws4_voice_one_active ON ws4_private.voice_sessions(incident_id)
  WHERE status IN ('ringing','answered');

CREATE TABLE ws4_private.voice_candidates (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES ws4_private.voice_sessions(id),
  sender_id uuid NOT NULL REFERENCES auth.users(id),
  operation_id uuid NOT NULL,
  candidate jsonb NOT NULL CHECK (jsonb_typeof(candidate)='object'
    AND octet_length(candidate::text) BETWEEN 2 AND 4096),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(session_id,sender_id,operation_id)
);
CREATE INDEX ws4_voice_candidate_poll ON ws4_private.voice_candidates(session_id,id);
ALTER TABLE ws4_private.voice_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.voice_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.voice_sessions,ws4_private.voice_candidates
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE ws4_private.voice_candidates_id_seq
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION ws4_private.voice_role(p_incident_id bigint) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_incident public.incidents%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_incident FROM public.incidents WHERE id=p_incident_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF v_incident.user_id=auth.uid() AND ws4_private.patient_active() THEN
    RETURN 'patient';
  END IF;
  IF v_incident.assigned_dispatcher_user_id=auth.uid()
     AND ws4_private.in_scope(v_incident.organisation_id) THEN
    RETURN 'dispatcher';
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION ws4_private.voice_role(bigint)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.corvia_ws4_voice_start(
  p_incident_id bigint,p_operation_id uuid,p_offer_sdp text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_prior ws4_private.voice_sessions%ROWTYPE; v_status text;
BEGIN
  IF ws4_private.voice_role(p_incident_id) IS DISTINCT FROM 'patient' THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  SELECT status INTO v_status FROM public.incidents WHERE id=p_incident_id;
  IF v_status NOT IN ('pending','in_progress') THEN
    RAISE EXCEPTION 'Incident is no longer active' USING ERRCODE='P0001';
  END IF;
  IF p_operation_id IS NULL OR p_offer_sdp IS NULL OR
     octet_length(p_offer_sdp) NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION 'Invalid voice offer' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ws4_voice:'||p_incident_id::text,0));
  SELECT * INTO v_prior FROM ws4_private.voice_sessions
    WHERE caller_id=auth.uid() AND start_operation_id=p_operation_id;
  IF FOUND THEN
    IF v_prior.incident_id<>p_incident_id OR v_prior.offer_sdp<>p_offer_sdp THEN
      RAISE EXCEPTION 'Voice operation reused with different input' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('session_id',v_prior.id,'status',v_prior.status);
  END IF;
  UPDATE ws4_private.voice_sessions SET status='timed_out',ended_at=now()
    WHERE incident_id=p_incident_id AND status='ringing'
      AND created_at<now()-interval '60 seconds';
  UPDATE ws4_private.voice_sessions SET status='ended',ended_at=now()
    WHERE incident_id=p_incident_id AND status='answered'
      AND created_at<now()-interval '60 minutes';
  IF EXISTS (SELECT 1 FROM ws4_private.voice_sessions
      WHERE incident_id=p_incident_id AND status IN ('ringing','answered')) THEN
    RAISE EXCEPTION 'A call is already active' USING ERRCODE='P0001';
  END IF;
  INSERT INTO ws4_private.voice_sessions(incident_id,caller_id,start_operation_id,offer_sdp)
    VALUES (p_incident_id,auth.uid(),p_operation_id,p_offer_sdp)
    RETURNING * INTO v_prior;
  RETURN jsonb_build_object('session_id',v_prior.id,'status',v_prior.status);
END $$;

CREATE FUNCTION public.corvia_ws4_voice_answer(
  p_incident_id bigint,p_session_id uuid,p_answer_sdp text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_session ws4_private.voice_sessions%ROWTYPE;
BEGIN
  IF ws4_private.voice_role(p_incident_id) IS DISTINCT FROM 'dispatcher' THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  IF p_answer_sdp IS NULL OR octet_length(p_answer_sdp) NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION 'Invalid voice answer' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_session FROM ws4_private.voice_sessions
    WHERE id=p_session_id AND incident_id=p_incident_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501'; END IF;
  IF v_session.status='answered' AND v_session.responder_id=auth.uid()
     AND v_session.answer_sdp=p_answer_sdp THEN
    RETURN jsonb_build_object('session_id',v_session.id,'status','answered');
  END IF;
  IF v_session.status<>'ringing' OR v_session.created_at<now()-interval '60 seconds'
     OR (SELECT status FROM public.incidents WHERE id=p_incident_id)
       NOT IN ('pending','in_progress') THEN
    RAISE EXCEPTION 'Voice offer is no longer active' USING ERRCODE='P0001';
  END IF;
  UPDATE ws4_private.voice_sessions SET responder_id=auth.uid(),
    answer_sdp=p_answer_sdp,status='answered',answered_at=now()
    WHERE id=p_session_id;
  RETURN jsonb_build_object('session_id',p_session_id,'status','answered');
END $$;

-- Developer 2 discovers only ringing calls on incidents they currently own.
CREATE FUNCTION public.corvia_ws4_voice_incoming() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'incident_id',q.incident_id::text,
    'session_id',q.id,
    'created_at',q.created_at) ORDER BY q.created_at),'[]'::jsonb)
  FROM (
    SELECT s.id,s.incident_id,s.created_at
    FROM ws4_private.voice_sessions s
    JOIN public.incidents i ON i.id=s.incident_id
    WHERE auth.uid() IS NOT NULL
      AND i.assigned_dispatcher_user_id=auth.uid()
      AND i.status IN ('pending','in_progress')
      AND ws4_private.in_scope(i.organisation_id)
      AND s.status='ringing'
      AND s.created_at>=now()-interval '60 seconds'
    ORDER BY s.created_at DESC LIMIT 20
  ) q;
$$;

CREATE FUNCTION public.corvia_ws4_voice_exchange(
  p_incident_id bigint,p_session_id uuid,p_after_id bigint DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_session ws4_private.voice_sessions%ROWTYPE; v_role text; v_candidates jsonb;
BEGIN
  v_role:=ws4_private.voice_role(p_incident_id);
  IF v_role IS NULL OR p_after_id<0 THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_session FROM ws4_private.voice_sessions
    WHERE id=p_session_id AND incident_id=p_incident_id;
  IF NOT FOUND OR (v_role='patient' AND v_session.caller_id<>auth.uid())
     OR (v_role='dispatcher' AND v_session.status='answered'
         AND v_session.responder_id<>auth.uid()) THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id::text,
      'candidate',c.candidate) ORDER BY c.id),'[]'::jsonb)
    INTO v_candidates FROM ws4_private.voice_candidates c
    WHERE c.session_id=p_session_id AND c.id>p_after_id
      AND c.sender_id<>auth.uid();
  RETURN jsonb_build_object('session_id',v_session.id,
    'status',CASE WHEN v_session.status='ringing'
                   AND v_session.created_at<now()-interval '60 seconds'
      THEN 'timed_out'
      WHEN v_session.status='answered'
                   AND v_session.created_at<now()-interval '60 minutes'
      THEN 'ended' ELSE v_session.status END,
    'offer_sdp',CASE WHEN v_role='dispatcher' THEN v_session.offer_sdp ELSE NULL END,
    'answer_sdp',CASE WHEN v_role='patient' THEN v_session.answer_sdp ELSE NULL END,
    'candidates',v_candidates);
END $$;

CREATE FUNCTION public.corvia_ws4_voice_candidate(
  p_incident_id bigint,p_session_id uuid,p_operation_id uuid,p_candidate jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_session ws4_private.voice_sessions%ROWTYPE; v_role text; v_id bigint;
BEGIN
  v_role:=ws4_private.voice_role(p_incident_id);
  SELECT * INTO v_session FROM ws4_private.voice_sessions
    WHERE id=p_session_id AND incident_id=p_incident_id FOR UPDATE;
  IF v_role IS NULL OR NOT FOUND OR p_operation_id IS NULL
     OR (v_role='patient' AND v_session.caller_id<>auth.uid())
     OR (v_role='dispatcher' AND (v_session.status<>'answered'
         OR v_session.responder_id<>auth.uid())) THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  IF v_session.status NOT IN ('ringing','answered')
     OR (v_session.status='ringing' AND v_session.created_at<now()-interval '60 seconds')
     OR v_session.created_at<now()-interval '60 minutes'
     OR jsonb_typeof(p_candidate) IS DISTINCT FROM 'object'
     OR octet_length(p_candidate::text) NOT BETWEEN 2 AND 4096 THEN
    RAISE EXCEPTION 'Invalid or expired voice candidate' USING ERRCODE='22023';
  END IF;
  SELECT id INTO v_id FROM ws4_private.voice_candidates
    WHERE session_id=p_session_id AND sender_id=auth.uid()
      AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (SELECT candidate FROM ws4_private.voice_candidates WHERE id=v_id)<>p_candidate THEN
      RAISE EXCEPTION 'Voice operation reused with different input' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('id',v_id::text);
  END IF;
  IF (SELECT count(*) FROM ws4_private.voice_candidates
      WHERE session_id=p_session_id)>=128 THEN
    RAISE EXCEPTION 'Voice candidate limit reached' USING ERRCODE='P0001';
  END IF;
  INSERT INTO ws4_private.voice_candidates(session_id,sender_id,operation_id,candidate)
    VALUES (p_session_id,auth.uid(),p_operation_id,p_candidate)
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('id',v_id::text);
END $$;

-- Owner-operated retention job. Do not put the service credential in Flutter.
CREATE FUNCTION public.corvia_ws4_voice_purge() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_deleted integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Voice maintenance denied' USING ERRCODE='42501';
  END IF;
  DELETE FROM ws4_private.voice_candidates c USING ws4_private.voice_sessions s
    WHERE c.session_id=s.id AND s.created_at<now()-interval '24 hours';
  DELETE FROM ws4_private.voice_sessions
    WHERE created_at<now()-interval '24 hours';
  GET DIAGNOSTICS v_deleted=ROW_COUNT;
  RETURN v_deleted;
END $$;

CREATE FUNCTION public.corvia_ws4_voice_end(p_incident_id bigint,p_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_session ws4_private.voice_sessions%ROWTYPE; v_role text;
BEGIN
  v_role:=ws4_private.voice_role(p_incident_id);
  SELECT * INTO v_session FROM ws4_private.voice_sessions
    WHERE id=p_session_id AND incident_id=p_incident_id FOR UPDATE;
  IF v_role IS NULL OR NOT FOUND
     OR (v_role='patient' AND v_session.caller_id<>auth.uid())
     OR (v_role='dispatcher' AND v_session.responder_id<>auth.uid()) THEN
    RAISE EXCEPTION 'Voice access denied' USING ERRCODE='42501';
  END IF;
  IF v_session.status IN ('ringing','answered') THEN
    UPDATE ws4_private.voice_sessions SET status='ended',ended_at=now()
      WHERE id=p_session_id;
    v_session.status:='ended';
  END IF;
  RETURN jsonb_build_object('session_id',p_session_id,'status',v_session.status);
END $$;

REVOKE ALL ON FUNCTION
  public.corvia_ws4_voice_start(bigint,uuid,text),
  public.corvia_ws4_voice_answer(bigint,uuid,text),
  public.corvia_ws4_voice_incoming(),
  public.corvia_ws4_voice_exchange(bigint,uuid,bigint),
  public.corvia_ws4_voice_candidate(bigint,uuid,uuid,jsonb),
  public.corvia_ws4_voice_end(bigint,uuid),
  public.corvia_ws4_voice_purge()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.corvia_ws4_voice_start(bigint,uuid,text),
  public.corvia_ws4_voice_answer(bigint,uuid,text),
  public.corvia_ws4_voice_incoming(),
  public.corvia_ws4_voice_exchange(bigint,uuid,bigint),
  public.corvia_ws4_voice_candidate(bigint,uuid,uuid,jsonb),
  public.corvia_ws4_voice_end(bigint,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_voice_purge() TO service_role;
COMMIT;
