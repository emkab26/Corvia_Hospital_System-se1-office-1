-- Candidate migration. Apply only after 001-007 on a reviewed, restorable target.
-- A requester is the account that opened the incident; this is not a claim
-- about the casualty. Never grant staff direct SELECT on patient profiles.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
BEGIN
  IF to_regclass('ws4_private.installation') IS NULL
     OR to_regprocedure('ws4_private.lock_workspace(bigint)') IS NULL
     OR to_regclass('public.incidents') IS NULL
     OR to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'WS4 core not installed; stop before identity migration';
  END IF;
  IF to_regprocedure('public.corvia_ws4_requester_identity(bigint)') IS NOT NULL THEN
    RAISE EXCEPTION 'Requester identity function already exists; inspect before changing it';
  END IF;
END $$;

CREATE FUNCTION public.corvia_ws4_requester_identity(p_incident_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_role text; v_incident public.incidents%ROWTYPE;
  v_first text; v_surname text; v_name text;
BEGIN
  v_role := ws4_private.lock_workspace(p_incident_id);
  SELECT * INTO v_incident FROM public.incidents WHERE id=p_incident_id;
  IF v_role NOT IN ('dispatch_supervisor','dispatcher') THEN
    RAISE EXCEPTION 'Requester identity access denied' USING ERRCODE='42501';
  END IF;
  SELECT nullif(btrim(first_name),''),nullif(btrim(surname),'')
    INTO v_first,v_surname FROM public.profiles
    WHERE user_id=v_incident.user_id AND is_active IS TRUE;
  v_name := nullif(btrim(concat_ws(' ',v_first,v_surname)),'');
  RETURN jsonb_build_object('incident_id',v_incident.id::text,
    'requester_name',v_name);
END $$;

REVOKE ALL ON FUNCTION public.corvia_ws4_requester_identity(bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.corvia_ws4_requester_identity(bigint)
  TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
