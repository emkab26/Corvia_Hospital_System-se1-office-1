-- Additive WS4 operations. Requires the reviewed 001-003 contract.
-- Provider simulation is OFF until the database owner explicitly enables it.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' OR to_regclass('ws4_dev_private.cancel_and_history_installation') IS NULL THEN
    RAISE EXCEPTION 'Reviewed WS4 base and database owner required';
  END IF;
END $$;

CREATE TABLE ws4_dev_private.operations_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  provider_demo_enabled boolean NOT NULL DEFAULT false
);
INSERT INTO ws4_dev_private.operations_settings DEFAULT VALUES;
CREATE TABLE ws4_dev_private.incident_workspace (
  incident_id bigint PRIMARY KEY REFERENCES public.incidents(id),
  priority text NOT NULL DEFAULT 'untriaged' CHECK(priority IN ('untriaged','urgent','standard')),
  provider_state text NOT NULL DEFAULT 'not_requested'
    CHECK(provider_state IN ('not_requested','accepted','rejected','unavailable','unknown','completed')),
  provider_request_id uuid,
  provider_reconciled_state text CHECK(provider_reconciled_state IN ('accepted','rejected','unavailable')),
  cancellation_requested boolean NOT NULL DEFAULT false
);
CREATE TABLE ws4_dev_private.dispatch_commands (
  actor_id uuid NOT NULL REFERENCES auth.users(id), operation_id uuid NOT NULL,
  incident_id bigint NOT NULL REFERENCES public.incidents(id), expected_version bigint NOT NULL,
  command text NOT NULL, payload jsonb NOT NULL, result jsonb NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,operation_id)
);
CREATE TABLE ws4_dev_private.messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  actor_id uuid NOT NULL REFERENCES auth.users(id), operation_id uuid NOT NULL,
  sender_role text NOT NULL CHECK(sender_role IN ('patient','dispatch')),
  body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 1000 AND btrim(body)<>''),
  recorded_at timestamptz NOT NULL DEFAULT now(), UNIQUE(actor_id,operation_id)
);
CREATE INDEX ws4_messages_incident ON ws4_dev_private.messages(incident_id,id);
CREATE INDEX ws4_commands_incident ON ws4_dev_private.dispatch_commands(incident_id,recorded_at);
ALTER TABLE ws4_dev_private.operations_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.incident_workspace ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.dispatch_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_dev_private.messages ENABLE ROW LEVEL SECURITY;

-- One lock order for reads and commands: profile, visible incident, authority.
-- Returns patient, dispatcher, or dispatch_supervisor; never trusts a client role.
CREATE FUNCTION ws4_dev_private.lock_workspace(p_incident_id bigint) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_profile_role text; v_i public.incidents%ROWTYPE; v_role text;
BEGIN
  SELECT role INTO v_profile_role FROM public.profiles WHERE user_id=auth.uid() AND is_active IS TRUE FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT i.* INTO v_i FROM public.incidents i WHERE id=p_incident_id AND (
    (user_id=auth.uid() AND v_profile_role='patient' AND EXISTS(SELECT 1 FROM ws4_dev_private.patient_routes r
      WHERE r.user_id=auth.uid() AND r.organisation_id=i.organisation_id)) OR ws4_dev_private.in_scope(i.organisation_id)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  IF v_i.user_id=auth.uid() AND v_profile_role='patient' THEN
    PERFORM 1 FROM ws4_dev_private.patient_routes WHERE user_id=auth.uid() AND organisation_id=v_i.organisation_id FOR SHARE;
    IF FOUND THEN RETURN 'patient'; END IF;
  END IF;
  SELECT role INTO v_role FROM ws4_dev_private.memberships WHERE user_id=auth.uid()
    AND organisation_id=v_i.organisation_id AND active IS TRUE FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  RETURN v_role;
END $$;

-- Fix the old trigger: notes and priority changes are updates, not new claims.
ALTER TABLE ws4_dev_private.incident_events DROP CONSTRAINT incident_events_event_type_check;
ALTER TABLE ws4_dev_private.incident_events ADD CHECK(event_type IN ('created','claimed','cancelled','resolved','updated'));
CREATE OR REPLACE FUNCTION ws4_dev_private.record_incident_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO ws4_dev_private.incident_events(incident_id,version,event_type,actor_user_id,previous_status,status)
  VALUES(NEW.id,NEW.version,CASE WHEN TG_OP='INSERT' THEN 'created'
    WHEN NEW.status=OLD.status THEN 'updated'
    WHEN NEW.status='in_progress' THEN 'claimed' ELSE NEW.status END,
    auth.uid(),CASE WHEN TG_OP='UPDATE' THEN OLD.status END,NEW.status);
  RETURN NEW;
END $$;

CREATE FUNCTION public.corvia_incident_workspace(p_incident_id bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_role text; v_i public.incidents%ROWTYPE; v_w ws4_dev_private.incident_workspace%ROWTYPE; v_notes jsonb; v_callback text;
BEGIN
  v_role:=ws4_dev_private.lock_workspace(p_incident_id);
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  SELECT * INTO v_w FROM ws4_dev_private.incident_workspace WHERE incident_id=p_incident_id;
  IF v_role<>'patient' AND (v_i.assigned_dispatcher_user_id=auth.uid() OR v_role='dispatch_supervisor') THEN
    SELECT coalesce(nullif(btrim(phone_number),''),nullif(btrim(phone),'')) INTO v_callback FROM public.profiles WHERE user_id=v_i.user_id;
    IF v_callback ~ '^[+0-9 ()-]+$' THEN v_callback:=regexp_replace(v_callback,'[^+0-9]','','g'); ELSE v_callback:=NULL; END IF;
    IF v_callback !~ '^\+?[0-9]{7,15}$' THEN v_callback:=NULL; END IF;
  END IF;
  IF v_role<>'patient' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('action',command,'text',payload->>'text','recorded_at',recorded_at)
      ORDER BY recorded_at DESC),'[]'::jsonb) INTO v_notes FROM
      (SELECT command,payload,recorded_at FROM ws4_dev_private.dispatch_commands WHERE incident_id=p_incident_id
       ORDER BY recorded_at DESC,operation_id DESC LIMIT 50) recent;
  END IF;
  RETURN jsonb_build_object('incident_id',v_i.id::text,'version',v_i.version::text,'status',v_i.status,
    'can_manage',coalesce(v_role<>'patient' AND (v_i.assigned_dispatcher_user_id=auth.uid() OR v_role='dispatch_supervisor') AND v_i.status='in_progress',false),
    'is_patient',v_role='patient','priority',coalesce(v_w.priority,'untriaged'),
    'provider_state',coalesce(v_w.provider_state,'not_requested'),'provider_demo',v_w.provider_request_id IS NOT NULL,
    'demo_available',(SELECT provider_demo_enabled FROM ws4_dev_private.operations_settings WHERE singleton),
    'cancellation_requested',coalesce(v_w.cancellation_requested,false),'recent_actions',coalesce(v_notes,'[]'::jsonb),
    'callback_number',v_callback);
END $$;

CREATE FUNCTION public.corvia_dispatch_command(p_incident_id bigint,p_operation_id uuid,p_expected_version bigint,p_command text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_role text; v_i public.incidents%ROWTYPE; v_old ws4_dev_private.dispatch_commands%ROWTYPE;
  v_w ws4_dev_private.incident_workspace%ROWTYPE; v_text text; v_result jsonb; v_has_assignment boolean;
BEGIN
  v_role:=ws4_dev_private.lock_workspace(p_incident_id);
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000' OR p_expected_version IS NULL OR p_expected_version<1
    OR p_command IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' THEN
    RAISE EXCEPTION 'Invalid command' USING ERRCODE='22023'; END IF;
  -- Actor-wide identity prevents reuse across incidents, including concurrent calls.
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':command:'||p_operation_id::text,0));
  SELECT * INTO v_old FROM ws4_dev_private.dispatch_commands WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (v_old.incident_id,v_old.expected_version,v_old.command,v_old.payload) IS DISTINCT FROM
       (p_incident_id,p_expected_version,p_command,p_payload) THEN
      RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  IF v_i.version<>p_expected_version OR v_i.status<>'in_progress' THEN
    RAISE EXCEPTION 'Incident changed or closed' USING ERRCODE='P0001'; END IF;
  IF (v_role='patient' AND p_command<>'request_cancellation') OR
     (v_role<>'patient' AND NOT (v_i.assigned_dispatcher_user_id=auth.uid() OR v_role='dispatch_supervisor')) THEN
    RAISE EXCEPTION 'Only the incident owner or scoped supervisor may manage this request' USING ERRCODE='42501'; END IF;
  IF (p_command='set_priority' AND NOT (p_payload ? 'priority' AND (p_payload-'priority'::text)='{}'::jsonb)) OR
     (p_command='simulate_provider' AND NOT (p_payload ? 'scenario' AND (p_payload-'scenario'::text)='{}'::jsonb)) OR
     (p_command='reconcile_provider' AND p_payload<>'{}'::jsonb) OR
     (p_command IN ('note','close','provider_completed','request_cancellation') AND NOT (p_payload ? 'text' AND (p_payload-'text'::text)='{}'::jsonb)) THEN
    RAISE EXCEPTION 'Unexpected command fields' USING ERRCODE='22023'; END IF;
  v_text:=p_payload->>'text';
  IF p_command IN ('note','close','provider_completed','request_cancellation') AND
      (jsonb_typeof(p_payload->'text')<>'string' OR v_text IS NULL OR char_length(v_text)>1000 OR btrim(v_text)='') THEN
    RAISE EXCEPTION 'A bounded reason or message is required' USING ERRCODE='22023'; END IF;
  INSERT INTO ws4_dev_private.incident_workspace(incident_id) VALUES(p_incident_id) ON CONFLICT DO NOTHING;
  SELECT * INTO v_w FROM ws4_dev_private.incident_workspace WHERE incident_id=p_incident_id;
  CASE p_command
  WHEN 'set_priority' THEN
    IF p_payload->>'priority' NOT IN ('untriaged','urgent','standard') OR p_payload->>'priority' IS NULL THEN
      RAISE EXCEPTION 'Invalid priority' USING ERRCODE='22023'; END IF;
    UPDATE ws4_dev_private.incident_workspace SET priority=p_payload->>'priority' WHERE incident_id=p_incident_id;
  WHEN 'note' THEN NULL;
  WHEN 'request_cancellation' THEN
    UPDATE ws4_dev_private.incident_workspace SET cancellation_requested=true WHERE incident_id=p_incident_id;
  WHEN 'simulate_provider' THEN
    IF NOT (SELECT provider_demo_enabled FROM ws4_dev_private.operations_settings WHERE singleton) THEN
      RAISE EXCEPTION 'Provider demo disabled' USING ERRCODE='42501'; END IF;
    IF v_w.provider_request_id IS NOT NULL THEN RAISE EXCEPTION 'Reconcile the existing provider request' USING ERRCODE='P0001'; END IF;
    IF p_payload->>'scenario' NOT IN ('accepted','rejected','unavailable','unknown') OR p_payload->>'scenario' IS NULL THEN
      RAISE EXCEPTION 'Invalid demo scenario' USING ERRCODE='22023'; END IF;
    UPDATE ws4_dev_private.incident_workspace SET provider_request_id=p_operation_id,
      provider_state=p_payload->>'scenario',provider_reconciled_state=CASE WHEN p_payload->>'scenario'='unknown' THEN 'accepted' ELSE p_payload->>'scenario' END
      WHERE incident_id=p_incident_id;
  WHEN 'reconcile_provider' THEN
    IF v_w.provider_state<>'unknown' THEN RAISE EXCEPTION 'No uncertain provider request' USING ERRCODE='P0001'; END IF;
    UPDATE ws4_dev_private.incident_workspace SET provider_state=provider_reconciled_state WHERE incident_id=p_incident_id;
  WHEN 'provider_completed' THEN
    IF v_w.provider_state<>'accepted' THEN RAISE EXCEPTION 'Provider acceptance required' USING ERRCODE='P0001'; END IF;
    UPDATE ws4_dev_private.incident_workspace SET provider_state='completed' WHERE incident_id=p_incident_id;
  WHEN 'close' THEN
    IF v_w.provider_state IN ('accepted','unknown') THEN RAISE EXCEPTION 'Reconcile or finish the provider response first' USING ERRCODE='P0001'; END IF;
    -- Existing Fleet assignments cannot be safely released without WS5/WS6's contract.
    IF to_regclass('public.incident_responder_assignments') IS NOT NULL THEN
      EXECUTE 'SELECT EXISTS(SELECT 1 FROM public.incident_responder_assignments WHERE incident_id=$1)' INTO v_has_assignment USING p_incident_id;
      IF v_has_assignment THEN RAISE EXCEPTION 'Fleet assignment requires its own completed handover/release' USING ERRCODE='P0001'; END IF;
    END IF;
  ELSE RAISE EXCEPTION 'Unsupported command' USING ERRCODE='22023';
  END CASE;
  UPDATE public.incidents SET status=CASE WHEN p_command='close' THEN 'resolved' ELSE status END WHERE id=p_incident_id RETURNING * INTO v_i;
  v_result:=jsonb_build_object('incident_id',v_i.id::text,'operation_id',p_operation_id,'version',v_i.version::text,'command',p_command);
  INSERT INTO ws4_dev_private.dispatch_commands(actor_id,operation_id,incident_id,expected_version,command,payload,result)
    VALUES(auth.uid(),p_operation_id,p_incident_id,p_expected_version,p_command,p_payload,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_send_incident_message(p_incident_id bigint,p_operation_id uuid,p_body text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_role text; v_i public.incidents%ROWTYPE; v_m ws4_dev_private.messages%ROWTYPE;
BEGIN
  v_role:=ws4_dev_private.lock_workspace(p_incident_id);
  IF p_operation_id IS NULL OR p_operation_id='00000000-0000-0000-0000-000000000000' OR p_body IS NULL OR char_length(p_body)>1000 OR btrim(p_body)='' THEN
    RAISE EXCEPTION 'Invalid message' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':message:'||p_operation_id::text,0));
  SELECT * INTO v_i FROM public.incidents WHERE id=p_incident_id;
  IF v_role<>'patient' AND NOT(v_i.assigned_dispatcher_user_id=auth.uid() OR v_role='dispatch_supervisor') THEN
    RAISE EXCEPTION 'Only the incident owner or scoped supervisor may send' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_m FROM ws4_dev_private.messages WHERE actor_id=auth.uid() AND operation_id=p_operation_id;
  IF FOUND THEN
    IF (v_m.incident_id,v_m.body) IS DISTINCT FROM (p_incident_id,p_body) THEN RAISE EXCEPTION 'Operation identity reused' USING ERRCODE='22023'; END IF;
  ELSE
    IF v_i.status NOT IN ('pending','in_progress') THEN RAISE EXCEPTION 'Incident closed' USING ERRCODE='P0001'; END IF;
    INSERT INTO ws4_dev_private.messages(incident_id,actor_id,operation_id,sender_role,body)
      VALUES(p_incident_id,auth.uid(),p_operation_id,CASE WHEN v_role='patient' THEN 'patient' ELSE 'dispatch' END,p_body) RETURNING * INTO v_m;
  END IF;
  RETURN jsonb_build_object('incident_id',p_incident_id::text,'operation_id',p_operation_id,'id',v_m.id::text,'recorded_at',v_m.recorded_at);
END $$;

CREATE FUNCTION public.corvia_incident_messages(p_incident_id bigint,p_before_id bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET TimeZone='UTC' AS $$
DECLARE v_messages jsonb; v_cursor bigint;
BEGIN
  PERFORM ws4_dev_private.lock_workspace(p_incident_id);
  IF p_before_id IS NOT NULL AND p_before_id<1 THEN RAISE EXCEPTION 'Invalid cursor' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',id::text,'sender',sender_role,'body',body,'recorded_at',recorded_at) ORDER BY id DESC),'[]'::jsonb),
    CASE WHEN count(*)=50 THEN min(id) END INTO v_messages,v_cursor
  FROM (SELECT * FROM ws4_dev_private.messages WHERE incident_id=p_incident_id AND (p_before_id IS NULL OR id<p_before_id) ORDER BY id DESC LIMIT 50) page;
  RETURN jsonb_build_object('incident_id',p_incident_id::text,'messages',v_messages,'next_cursor',v_cursor::text);
END $$;

-- Keep the existing access projection, adding one capability for the new panel.
CREATE OR REPLACE FUNCTION public.corvia_dispatch_access_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_memberships jsonb;
BEGIN
  IF NOT public.corvia_is_dispatch_operator() THEN RAISE EXCEPTION 'Access denied' USING ERRCODE='42501'; END IF;
  SELECT jsonb_agg(jsonb_build_object('organisation_id',organisation_id,'role',role) ORDER BY organisation_id)
    INTO v_memberships FROM ws4_dev_private.memberships WHERE user_id=auth.uid() AND active IS TRUE;
  RETURN jsonb_build_object('user_id',auth.uid(),'memberships',v_memberships,
    'capabilities',jsonb_build_array('read_incidents','claim_incident','read_intake_details','read_incident_history','incident_workspace'),
    'policy_version','ws4-dev-core-1','server_time',now());
END $$;
REVOKE ALL ON ws4_dev_private.operations_settings,ws4_dev_private.incident_workspace,ws4_dev_private.dispatch_commands,ws4_dev_private.messages FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE ws4_dev_private.messages_id_seq FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION ws4_dev_private.lock_workspace(bigint),public.corvia_incident_workspace(bigint),
  public.corvia_dispatch_command(bigint,uuid,bigint,text,jsonb),public.corvia_send_incident_message(bigint,uuid,text),public.corvia_incident_messages(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_incident_workspace(bigint),public.corvia_dispatch_command(bigint,uuid,bigint,text,jsonb),
  public.corvia_send_incident_message(bigint,uuid,text),public.corvia_incident_messages(bigint,bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
