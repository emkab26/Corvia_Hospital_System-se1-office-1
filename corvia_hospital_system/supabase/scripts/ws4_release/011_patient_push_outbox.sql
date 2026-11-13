-- Candidate, provider-neutral device push contract. This does not obtain a
-- device token, send a push, or establish delivery. Install only after 001
-- on a backed-up reviewed target with a selected provider and worker plan.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $$ BEGIN
  IF to_regclass('ws4_private.incident_events') IS NULL
     OR to_regprocedure('ws4_private.patient_intake_scope()') IS NULL THEN
    RAISE EXCEPTION 'WS4 core must be installed first';
  END IF;
  IF to_regclass('ws4_private.push_subscriptions') IS NOT NULL THEN
    RAISE EXCEPTION 'Push subscriptions already exist; inspect before changing';
  END IF;
END $$;

CREATE TABLE ws4_private.push_subscriptions (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  installation_id uuid NOT NULL,
  provider text NOT NULL CHECK (provider IN ('fcm','webpush')),
  token text NOT NULL CHECK (char_length(token) BETWEEN 40 AND 4096),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,installation_id),
  UNIQUE (provider,token)
);
CREATE TABLE ws4_private.push_outbox (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  event_version bigint NOT NULL,
  event_type text NOT NULL,
  installation_id uuid NOT NULL,
  provider text NOT NULL,
  token text NOT NULL,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','processing','provider_accepted','delivered','failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  provider_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (incident_id,event_version,installation_id)
);
CREATE INDEX ws4_push_claim ON ws4_private.push_outbox(next_attempt_at,id)
  WHERE status IN ('queued','processing');
ALTER TABLE ws4_private.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ws4_private.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.push_subscriptions,ws4_private.push_outbox
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE ws4_private.push_outbox_id_seq
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.corvia_ws4_push_register(
  p_installation_id uuid,p_provider text,p_token text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid();
BEGIN
  PERFORM ws4_private.patient_intake_scope();
  IF p_installation_id IS NULL OR
     p_provider NOT IN ('fcm','webpush') OR
     char_length(p_token) NOT BETWEEN 40 AND 4096 THEN
    RAISE EXCEPTION 'Invalid push subscription' USING ERRCODE='22023';
  END IF;
  -- A rotated or reused token must not continue delivering the old account's
  -- events to this device. Registration atomically transfers that token.
  PERFORM pg_advisory_xact_lock(hashtextextended('ws4_push:'||p_provider||':'||p_token,0));
  UPDATE ws4_private.push_outbox SET status='failed',updated_at=now(),lease_until=NULL
    WHERE status IN ('queued','processing') AND (
      (provider=p_provider AND token=p_token AND
       (user_id<>v_actor OR installation_id<>p_installation_id))
      OR (user_id=v_actor AND installation_id=p_installation_id AND
          (provider<>p_provider OR token<>p_token)));
  DELETE FROM ws4_private.push_subscriptions
    WHERE provider=p_provider AND token=p_token;
  IF (SELECT count(*) FROM ws4_private.push_subscriptions
      WHERE user_id=v_actor AND installation_id<>p_installation_id)>=5 THEN
    RAISE EXCEPTION 'Too many device subscriptions' USING ERRCODE='22023';
  END IF;
  INSERT INTO ws4_private.push_subscriptions
    (user_id,installation_id,provider,token)
  VALUES(v_actor,p_installation_id,p_provider,p_token)
  ON CONFLICT (user_id,installation_id) DO UPDATE
    SET provider=excluded.provider,token=excluded.token,updated_at=now();
  RETURN true;
END $$;

CREATE FUNCTION public.corvia_ws4_push_revoke(p_installation_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid(); v_removed integer;
BEGIN
  IF v_actor IS NULL OR p_installation_id IS NULL THEN
    RAISE EXCEPTION 'Push subscription access denied' USING ERRCODE='42501';
  END IF;
  DELETE FROM ws4_private.push_subscriptions
    WHERE user_id=v_actor AND installation_id=p_installation_id;
  GET DIAGNOSTICS v_removed=ROW_COUNT;
  UPDATE ws4_private.push_outbox SET status='failed',updated_at=now(),lease_until=NULL
    WHERE user_id=v_actor AND installation_id=p_installation_id
      AND status IN ('queued','processing');
  RETURN v_removed=1;
END $$;

CREATE FUNCTION ws4_private.enqueue_patient_push() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.event_type NOT IN ('created','claimed','resolved','cancelled') THEN
    RETURN NEW;
  END IF;
  INSERT INTO ws4_private.push_outbox
    (incident_id,user_id,event_version,event_type,installation_id,provider,token)
  SELECT NEW.incident_id,i.user_id,NEW.version,NEW.event_type,
         s.installation_id,s.provider,s.token
  FROM public.incidents i JOIN ws4_private.push_subscriptions s
    ON s.user_id=i.user_id
  WHERE i.id=NEW.incident_id
  ON CONFLICT (incident_id,event_version,installation_id) DO NOTHING;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_enqueue_patient_push
AFTER INSERT ON ws4_private.incident_events
FOR EACH ROW EXECUTE FUNCTION ws4_private.enqueue_patient_push();

-- Service-only worker. Payload is generic on lock screens; incident ID is an
-- opaque navigation hint and must be re-authorised by the app after login.
CREATE FUNCTION public.corvia_ws4_push_claim(p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_result jsonb;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'Push worker access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.push_outbox SET status='failed',lease_until=NULL,updated_at=now()
    WHERE status='processing' AND lease_until<now() AND attempts>=5;
  WITH selected AS (
    SELECT q.id FROM ws4_private.push_outbox q
    WHERE ((q.status='queued' AND q.next_attempt_at<=now())
       OR (q.status='processing' AND q.lease_until<now()))
      AND EXISTS (SELECT 1 FROM ws4_private.push_subscriptions s
        WHERE s.user_id=q.user_id AND s.installation_id=q.installation_id
          AND s.provider=q.provider AND s.token=q.token)
    ORDER BY next_attempt_at,id LIMIT p_limit FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE ws4_private.push_outbox q
    SET status='processing',attempts=q.attempts+1,
      lease_until=now()+interval '2 minutes',updated_at=now()
    FROM selected s WHERE q.id=s.id AND q.attempts<5
    RETURNING q.id,q.incident_id,q.provider,q.token
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'alert_id',id::text,'incident_id',incident_id::text,
    'provider',provider,'token',token,
    'title','Corvia update','body','Your emergency request has an update.')),
    '[]'::jsonb) INTO v_result FROM claimed;
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_push_receipt(
  p_alert_id bigint,p_provider_reference text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_updated integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR nullif(btrim(p_provider_reference),'') IS NULL
     OR char_length(p_provider_reference)>200 THEN
    RAISE EXCEPTION 'Push receipt access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.push_outbox SET status='delivered',updated_at=now()
    WHERE id=p_alert_id AND status='provider_accepted'
      AND provider_reference=p_provider_reference;
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  RETURN v_updated=1;
END $$;

CREATE FUNCTION public.corvia_ws4_push_ack(
  p_alert_id bigint,p_result text,p_provider_reference text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_updated integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR p_result NOT IN ('provider_accepted','delivered','retry')
     OR char_length(p_provider_reference)>200 THEN
    RAISE EXCEPTION 'Push worker access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.push_outbox SET
    status=CASE WHEN p_result='retry' THEN
      CASE WHEN attempts>=5 THEN 'failed' ELSE 'queued' END ELSE p_result END,
    next_attempt_at=CASE WHEN p_result='retry'
      THEN now()+attempts*interval '5 minutes' ELSE next_attempt_at END,
    lease_until=NULL,provider_reference=nullif(p_provider_reference,''),updated_at=now()
  WHERE id=p_alert_id AND status='processing' AND lease_until>=now();
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  RETURN v_updated=1;
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_push_register(uuid,text,text),
  public.corvia_ws4_push_revoke(uuid),public.corvia_ws4_push_claim(integer),
  public.corvia_ws4_push_ack(bigint,text,text),
  public.corvia_ws4_push_receipt(bigint,text),
  ws4_private.enqueue_patient_push()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_push_register(uuid,text,text),
  public.corvia_ws4_push_revoke(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_push_claim(integer),
  public.corvia_ws4_push_ack(bigint,text,text),
  public.corvia_ws4_push_receipt(bigint,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
