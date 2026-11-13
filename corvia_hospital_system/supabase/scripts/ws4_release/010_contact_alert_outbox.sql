-- Candidate migration. Durable, minimal contact alerts; no SMS or push is sent
-- by this script. Install only after WS4 core on a backed-up reviewed target.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF to_regclass('ws4_private.patient_intake_operations') IS NULL
     OR to_regprocedure('ws4_private.patient_intake_scope()') IS NULL THEN
    RAISE EXCEPTION 'WS4 patient intake must be installed first';
  END IF;
  IF to_regclass('ws4_private.emergency_contacts') IS NOT NULL
     OR to_regclass('ws4_private.contact_alert_outbox') IS NOT NULL THEN
    RAISE EXCEPTION 'Contact alert contract already exists; inspect it first';
  END IF;
END $$;

CREATE TABLE ws4_private.emergency_contacts (
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  id uuid NOT NULL,
  name text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 60),
  relationship text NOT NULL CHECK (char_length(relationship) BETWEEN 2 AND 30),
  phone_number text NOT NULL CHECK (phone_number ~ '^\+?[0-9]{7,15}$'),
  is_primary boolean NOT NULL DEFAULT false,
  notify_on_emergency boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,id)
);
CREATE UNIQUE INDEX ws4_one_primary_contact
  ON ws4_private.emergency_contacts(user_id) WHERE is_primary;
ALTER TABLE ws4_private.emergency_contacts ENABLE ROW LEVEL SECURITY;

CREATE TABLE ws4_private.contact_alert_outbox (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  incident_id bigint NOT NULL REFERENCES public.incidents(id),
  user_id uuid NOT NULL REFERENCES public.profiles(user_id),
  contact_id uuid NOT NULL,
  phone_number text NOT NULL CHECK (phone_number ~ '^\+?[0-9]{7,15}$'),
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','processing','provider_accepted','delivered','failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  provider_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (incident_id,contact_id)
);
CREATE INDEX ws4_alert_claim ON ws4_private.contact_alert_outbox
  (next_attempt_at,id) WHERE status IN ('queued','processing');
ALTER TABLE ws4_private.contact_alert_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ws4_private.emergency_contacts,
  ws4_private.contact_alert_outbox FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE ws4_private.contact_alert_outbox_id_seq
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.corvia_ws4_contacts_get() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid(); v_result jsonb;
BEGIN
  PERFORM ws4_private.patient_intake_scope();
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'name',name,'relationship',relationship,
    'phone_number',phone_number,'is_primary',is_primary,
    'notify_on_emergency',notify_on_emergency)
    ORDER BY is_primary DESC,name,id),'[]'::jsonb) INTO v_result
  FROM ws4_private.emergency_contacts WHERE user_id=v_actor;
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_contacts_replace(p_contacts jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid(); v_item jsonb; v_id uuid;
  v_name text; v_relationship text; v_phone text;
  v_primary boolean; v_notify boolean;
BEGIN
  PERFORM ws4_private.patient_intake_scope();
  IF jsonb_typeof(p_contacts) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_contacts)>5
     OR octet_length(p_contacts::text)>5000 THEN
    RAISE EXCEPTION 'Invalid contacts' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('ws4_contacts:'||v_actor::text,0));
  DELETE FROM ws4_private.emergency_contacts WHERE user_id=v_actor;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_contacts) LOOP
    IF jsonb_typeof(v_item) IS DISTINCT FROM 'object'
       OR (v_item->>'id') IS NULL
       OR (v_item->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR jsonb_typeof(v_item->'is_primary') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_item->'notify_on_emergency') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'Invalid contact fields' USING ERRCODE='22023';
    END IF;
    v_id := (v_item->>'id')::uuid;
    v_name := nullif(btrim(v_item->>'name'),'');
    v_relationship := nullif(btrim(v_item->>'relationship'),'');
    v_phone := nullif(btrim(v_item->>'phone_number'),'');
    v_primary := (v_item->>'is_primary')::boolean;
    v_notify := (v_item->>'notify_on_emergency')::boolean;
    IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 2 AND 60
       OR v_relationship IS NULL OR char_length(v_relationship) NOT BETWEEN 2 AND 30
       OR v_phone IS NULL OR char_length(v_phone)>40
       OR v_phone !~ '^[+0-9 ()-]+$' THEN
      RAISE EXCEPTION 'Invalid contact data' USING ERRCODE='22023';
    END IF;
    v_phone := regexp_replace(v_phone,'[^+0-9]','','g');
    IF v_phone !~ '^\+?[0-9]{7,15}$' THEN
      RAISE EXCEPTION 'Invalid contact phone' USING ERRCODE='22023';
    END IF;
    INSERT INTO ws4_private.emergency_contacts
      (user_id,id,name,relationship,phone_number,is_primary,notify_on_emergency)
    VALUES (v_actor,v_id,v_name,v_relationship,v_phone,v_primary,v_notify);
  END LOOP;
  RETURN public.corvia_ws4_contacts_get();
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Duplicate contact or primary contact' USING ERRCODE='22023';
END $$;

-- Fired only by a confirmed WS4 patient-intake operation. Never hold up the
-- incident for an external provider: this writes a local row in the same
-- transaction; transport is performed asynchronously by a service worker.
CREATE FUNCTION ws4_private.enqueue_contact_alerts() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO ws4_private.contact_alert_outbox
    (incident_id,user_id,contact_id,phone_number)
  SELECT NEW.incident_id,NEW.user_id,c.id,c.phone_number
  FROM ws4_private.emergency_contacts c
  WHERE c.user_id=NEW.user_id AND c.notify_on_emergency IS TRUE
  ON CONFLICT (incident_id,contact_id) DO NOTHING;
  RETURN NEW;
END $$;
CREATE TRIGGER ws4_enqueue_contact_alerts
AFTER INSERT ON ws4_private.patient_intake_operations
FOR EACH ROW EXECUTE FUNCTION ws4_private.enqueue_contact_alerts();

CREATE FUNCTION public.corvia_ws4_contact_alert_status(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid := auth.uid(); v_counts jsonb;
BEGIN
  PERFORM ws4_private.patient_intake_scope();
  IF NOT EXISTS (SELECT 1 FROM public.incidents i
      WHERE i.id=p_incident_id AND i.user_id=v_actor) THEN
    RAISE EXCEPTION 'Alert access denied' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_build_object(
    'queued',count(*) FILTER (WHERE status IN ('queued','processing')),
    'provider_accepted',count(*) FILTER (WHERE status='provider_accepted'),
    'delivered',count(*) FILTER (WHERE status='delivered'),
    'failed',count(*) FILTER (WHERE status='failed')) INTO v_counts
  FROM ws4_private.contact_alert_outbox
  WHERE incident_id=p_incident_id AND user_id=v_actor;
  RETURN jsonb_build_object('incident_id',p_incident_id::text,'counts',v_counts);
END $$;

-- Service-only queue contract. A transport worker sends a generic message,
-- using alert_id as its provider idempotency key. No health/location details
-- leave this function. Provider acceptance is not proof of delivery.
CREATE FUNCTION public.corvia_ws4_contact_alert_claim(p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_result jsonb;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'Alert worker access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.contact_alert_outbox
    SET status='failed',lease_until=NULL,updated_at=now()
    WHERE status='processing' AND lease_until<now() AND attempts>=5;
  WITH selected AS (
    SELECT id FROM ws4_private.contact_alert_outbox
    WHERE (status='queued' AND next_attempt_at<=now())
       OR (status='processing' AND lease_until<now())
    ORDER BY next_attempt_at,id LIMIT p_limit FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE ws4_private.contact_alert_outbox q
    SET status='processing',attempts=q.attempts+1,
      lease_until=now()+interval '2 minutes',updated_at=now()
    FROM selected s WHERE q.id=s.id AND q.attempts<5
    RETURNING q.id,q.phone_number
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'alert_id',id::text,'phone_number',phone_number,
    'message','A Corvia contact requested emergency assistance. Please call them directly.')),'[]'::jsonb)
  INTO v_result FROM claimed;
  RETURN v_result;
END $$;

CREATE FUNCTION public.corvia_ws4_contact_alert_receipt(
  p_alert_id bigint,p_provider_reference text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_updated integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR nullif(btrim(p_provider_reference),'') IS NULL THEN
    RAISE EXCEPTION 'Alert receipt access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.contact_alert_outbox
    SET status='delivered',updated_at=now()
    WHERE id=p_alert_id AND status='provider_accepted'
      AND provider_reference=p_provider_reference;
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  RETURN v_updated=1;
END $$;

CREATE FUNCTION public.corvia_ws4_contact_alert_ack(
  p_alert_id bigint,p_result text,p_provider_reference text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_updated integer;
BEGIN
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
     OR p_result NOT IN ('provider_accepted','delivered','retry')
     OR char_length(p_provider_reference)>200 THEN
    RAISE EXCEPTION 'Alert worker access denied' USING ERRCODE='42501';
  END IF;
  UPDATE ws4_private.contact_alert_outbox
  SET status=CASE WHEN p_result='retry' THEN
        CASE WHEN attempts>=5 THEN 'failed' ELSE 'queued' END
      ELSE p_result END,
    next_attempt_at=CASE WHEN p_result='retry'
      THEN now()+attempts*interval '5 minutes' ELSE next_attempt_at END,
    lease_until=NULL,provider_reference=nullif(p_provider_reference,''),
    updated_at=now()
  WHERE id=p_alert_id AND status='processing' AND lease_until>=now();
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  RETURN v_updated=1;
END $$;

REVOKE ALL ON FUNCTION
  public.corvia_ws4_contacts_get(),
  public.corvia_ws4_contacts_replace(jsonb),
  public.corvia_ws4_contact_alert_status(bigint),
  public.corvia_ws4_contact_alert_claim(integer),
  public.corvia_ws4_contact_alert_ack(bigint,text,text),
  public.corvia_ws4_contact_alert_receipt(bigint,text),
  ws4_private.enqueue_contact_alerts()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_contacts_get(),
  public.corvia_ws4_contacts_replace(jsonb),
  public.corvia_ws4_contact_alert_status(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_contact_alert_claim(integer),
  public.corvia_ws4_contact_alert_ack(bigint,text,text),
  public.corvia_ws4_contact_alert_receipt(bigint,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
