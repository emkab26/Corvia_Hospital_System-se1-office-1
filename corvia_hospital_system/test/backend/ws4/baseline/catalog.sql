-- TEST BASELINE ONLY: contains known permission defects, never deploy.
-- Extracted selected catalog contract, not a complete Supabase database.
CREATE ROLE supabase_admin NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
-- Synthetic identity boundary: models only auth UID, not Auth/JWT verification.
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
GRANT USAGE ON SCHEMA auth, public TO anon, authenticated, service_role, supabase_admin;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
-- Resolve deparsed catalog uid()/REFERENCES users to auth.
SET search_path = public, auth;
-- Dependency stub only: preserves the actual profile trigger's dispatch branch.
-- Does not model or certify the lab product's tables/permissions.
CREATE TABLE public.lab_worker_accounts (
  profile_id uuid, is_active boolean, can_verify_results boolean, updated_at timestamptz
);
ALTER TABLE public.lab_worker_accounts OWNER TO supabase_admin;


CREATE TABLE public.profiles (
  "user_id" uuid NOT NULL,
  "id_number" text,
  "first_name" text,
  "surname" text,
  "email" text,
  "address" text,
  "created_at" timestamp with time zone DEFAULT now(),
  "phone_number" text,
  "profile_picture_url" text,
  "updated_at" timestamp with time zone DEFAULT now(),
  "user_type" text DEFAULT 'patient'::text NOT NULL,
  "date_of_birth" date,
  "id" uuid DEFAULT gen_random_uuid(),
  "phone" text,
  "role" text DEFAULT 'patient'::text,
  "avatar_url" text,
  "is_active" boolean DEFAULT true,
  "profile_complete" boolean DEFAULT false
);

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_email_key" UNIQUE (email);

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_id_number_key" UNIQUE (id_number);

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_pkey" PRIMARY KEY (user_id);

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_role_check" CHECK (((role IS NULL) OR (role = ANY (ARRAY['admin'::text, 'doctor'::text, 'hospital_admin'::text, 'nurse'::text, 'patient'::text, 'pharmacist'::text, 'reception'::text, 'receptionist'::text, 'specialist'::text, 'dispatcher'::text, 'dispatch_supervisor'::text, 'lab_worker'::text, 'lab_technician'::text, 'laboratory_technician'::text, 'laboratory_worker'::text, 'private_lab_admin'::text, 'private_lab_administrator'::text, 'lab_admin'::text]))));

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id);

ALTER TABLE public.profiles ADD CONSTRAINT "profiles_user_type_check" CHECK (((user_type IS NULL) OR (user_type = ANY ('{admin,doctor,hospital_admin,nurse,patient,pharmacist,reception,receptionist,specialist}'::text[]))));

CREATE INDEX idx_profiles_user_id ON public.profiles USING btree (user_id);

CREATE UNIQUE INDEX profiles_id_unique_idx ON public.profiles USING btree (id);

CREATE INDEX profiles_role_idx ON public.profiles USING btree (role);

CREATE INDEX profiles_user_id_idx ON public.profiles USING btree (user_id);

CREATE UNIQUE INDEX profiles_user_id_unique_idx ON public.profiles USING btree (user_id) WHERE (user_id IS NOT NULL);

ALTER TABLE public.profiles OWNER TO supabase_admin;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles TO service_role;

CREATE TABLE public.incidents (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "user_id" uuid,
  "latitude" double precision NOT NULL,
  "longitude" double precision NOT NULL,
  "status" text DEFAULT 'pending'::text,
  "created_at" timestamp with time zone DEFAULT now(),
  "last_viewed_at" timestamp with time zone,
  "assigned_dispatcher_user_id" uuid,
  "accepted_at" timestamp with time zone
);

ALTER TABLE public.incidents ADD CONSTRAINT "incidents_assigned_dispatcher_user_id_fkey" FOREIGN KEY (assigned_dispatcher_user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE public.incidents ADD CONSTRAINT "incidents_pkey" PRIMARY KEY (id);

ALTER TABLE public.incidents ADD CONSTRAINT "incidents_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(user_id);

CREATE INDEX incidents_assigned_dispatcher_status_idx ON public.incidents USING btree (assigned_dispatcher_user_id, status, created_at DESC);

ALTER TABLE public.incidents OWNER TO supabase_admin;

ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.incidents TO anon;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.incidents TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.incidents TO service_role;

CREATE OR REPLACE FUNCTION public.block_user_type_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.user_type != OLD.user_type THEN
    RAISE EXCEPTION 'user_type cannot be changed by the client';
  END IF;
  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.block_user_type_change() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.block_user_type_change() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.block_user_type_change() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.block_user_type_change() TO anon;

GRANT EXECUTE ON FUNCTION public.block_user_type_change() TO authenticated;

GRANT EXECUTE ON FUNCTION public.block_user_type_change() TO service_role;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

ALTER FUNCTION public.set_updated_at() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.set_updated_at() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.set_updated_at() TO anon;

GRANT EXECUTE ON FUNCTION public.set_updated_at() TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_updated_at() TO service_role;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = auth.uid() AND user_type = 'admin')
$function$;

ALTER FUNCTION public.is_admin() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;

CREATE OR REPLACE FUNCTION public.corvia_lab_admin_disable_worker()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_profile_id uuid;
begin
  if tg_table_name = 'profiles' then
    if lower(coalesce(new.role,'')) not in (
      'lab_admin','private_lab_admin','private_lab_administrator'
    ) then
      return new;
    end if;
    v_profile_id := new.id;
  else
    if new.is_active is false then
      return new;
    end if;
    v_profile_id := new.profile_id;
  end if;

  update public.lab_worker_accounts
  set is_active = false,
      can_verify_results = false,
      updated_at = now()
  where profile_id = v_profile_id;

  return new;
end;
$function$;

ALTER FUNCTION public.corvia_lab_admin_disable_worker() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.corvia_lab_admin_disable_worker() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.corvia_lab_admin_disable_worker() TO service_role;

CREATE OR REPLACE FUNCTION public.corvia_is_dispatch_operator()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1
    from public.profiles profile
    where profile.user_id = auth.uid()
      and profile.is_active is distinct from false
      and lower(
        replace(
          replace(coalesce(profile.role, ''), '-', '_'),
          ' ',
          '_'
        )
      ) in ('dispatcher', 'dispatch_supervisor')
  );
$function$;

ALTER FUNCTION public.corvia_is_dispatch_operator() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.corvia_is_dispatch_operator() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.corvia_is_dispatch_operator() TO anon;

GRANT EXECUTE ON FUNCTION public.corvia_is_dispatch_operator() TO authenticated;

GRANT EXECUTE ON FUNCTION public.corvia_is_dispatch_operator() TO service_role;

CREATE OR REPLACE FUNCTION public.corvia_protect_incident_dispatch_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'INSERT'
     and (
       new.assigned_dispatcher_user_id is not null
       or new.accepted_at is not null
     )
     and not public.corvia_is_dispatch_operator() then
    raise exception 'Dispatch assignment fields can only be changed by dispatch.'
      using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE'
     and (
       new.assigned_dispatcher_user_id is distinct from old.assigned_dispatcher_user_id
       or new.accepted_at is distinct from old.accepted_at
     )
     and not public.corvia_is_dispatch_operator() then
    raise exception 'Dispatch assignment fields can only be changed by dispatch.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

ALTER FUNCTION public.corvia_protect_incident_dispatch_assignment() OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.corvia_protect_incident_dispatch_assignment() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.corvia_protect_incident_dispatch_assignment() TO anon;

GRANT EXECUTE ON FUNCTION public.corvia_protect_incident_dispatch_assignment() TO authenticated;

GRANT EXECUTE ON FUNCTION public.corvia_protect_incident_dispatch_assignment() TO service_role;

CREATE OR REPLACE FUNCTION public.corvia_dispatch_accept_incident(p_incident_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_incident public.incidents%rowtype;
  v_status text;
begin
  if not public.corvia_is_dispatch_operator() then
    raise exception 'Only an active dispatcher can accept emergencies.'
      using errcode = '42501';
  end if;

  select incident.*
  into v_incident
  from public.incidents incident
  where incident.id = p_incident_id
  for update;

  if not found then
    raise exception 'The emergency no longer exists.'
      using errcode = 'P0002';
  end if;

  v_status := lower(
    replace(
      replace(coalesce(v_incident.status, ''), '-', '_'),
      ' ',
      '_'
    )
  );

  -- A retry from the dispatcher who already claimed the incident is safe and
  -- returns the same assignment instead of creating a conflict.
  if v_incident.assigned_dispatcher_user_id = auth.uid()
     and v_status = 'in_progress' then
    return jsonb_build_object(
      'id', v_incident.id,
      'user_id', v_incident.user_id,
      'latitude', v_incident.latitude,
      'longitude', v_incident.longitude,
      'status', v_incident.status,
      'created_at', v_incident.created_at,
      'assigned_dispatcher_user_id', v_incident.assigned_dispatcher_user_id,
      'accepted_at', v_incident.accepted_at
    );
  end if;

  if v_status <> 'pending'
     or v_incident.assigned_dispatcher_user_id is not null then
    raise exception 'This emergency has already been accepted or is no longer pending.'
      using errcode = 'P0001';
  end if;

  update public.incidents incident
  set status = 'in_progress',
      assigned_dispatcher_user_id = auth.uid(),
      accepted_at = now()
  where incident.id = p_incident_id
  returning incident.* into v_incident;

  return jsonb_build_object(
    'id', v_incident.id,
    'user_id', v_incident.user_id,
    'latitude', v_incident.latitude,
    'longitude', v_incident.longitude,
    'status', v_incident.status,
    'created_at', v_incident.created_at,
    'assigned_dispatcher_user_id', v_incident.assigned_dispatcher_user_id,
    'accepted_at', v_incident.accepted_at
  );
end;
$function$;

ALTER FUNCTION public.corvia_dispatch_accept_incident(bigint) OWNER TO supabase_admin;

REVOKE ALL ON FUNCTION public.corvia_dispatch_accept_incident(bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.corvia_dispatch_accept_incident(bigint) TO anon;

GRANT EXECUTE ON FUNCTION public.corvia_dispatch_accept_incident(bigint) TO authenticated;

GRANT EXECUTE ON FUNCTION public.corvia_dispatch_accept_incident(bigint) TO service_role;

CREATE TRIGGER protect_incident_dispatch_assignment BEFORE UPDATE OF assigned_dispatcher_user_id, accepted_at ON public.incidents FOR EACH ROW EXECUTE FUNCTION corvia_protect_incident_dispatch_assignment();

CREATE TRIGGER protect_incident_dispatch_assignment_on_insert BEFORE INSERT ON public.incidents FOR EACH ROW EXECUTE FUNCTION corvia_protect_incident_dispatch_assignment();

CREATE TRIGGER corvia_lab_admin_disable_worker BEFORE INSERT OR UPDATE OF role ON public.profiles FOR EACH ROW EXECUTE FUNCTION corvia_lab_admin_disable_worker();

CREATE TRIGGER profiles_block_user_type_change BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION block_user_type_change();

CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE POLICY "corvia_dispatch_read_incidents" ON public.incidents AS PERMISSIVE FOR SELECT TO "authenticated" USING (corvia_is_dispatch_operator());

CREATE POLICY "corvia_patient_insert_own_incident" ON public.incidents AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((uid() = user_id));

CREATE POLICY "corvia_patient_read_own_incident" ON public.incidents AS PERMISSIVE FOR SELECT TO "authenticated" USING ((uid() = user_id));

CREATE POLICY "corvia_patient_update_own_incident" ON public.incidents AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((uid() = user_id)) WITH CHECK ((uid() = user_id));

CREATE POLICY "incidents_insert" ON public.incidents AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((user_id = uid()));

CREATE POLICY "incidents_select" ON public.incidents AS PERMISSIVE FOR SELECT TO "authenticated" USING (((user_id = uid()) OR is_admin()));

CREATE POLICY "incidents_update" ON public.incidents AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((user_id = uid()) OR is_admin()));

CREATE POLICY "Users read own base profile" ON public.profiles AS PERMISSIVE FOR SELECT TO "authenticated" USING ((user_id = uid()));

CREATE POLICY "Users update own base profile" ON public.profiles AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((user_id = uid())) WITH CHECK ((user_id = uid()));

CREATE POLICY "profiles_insert_own" ON public.profiles AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((user_id = uid()) OR (id = uid())));

CREATE POLICY "profiles_select_own" ON public.profiles AS PERMISSIVE FOR SELECT TO "authenticated" USING (((user_id = uid()) OR (id = uid())));

CREATE POLICY "profiles_update_own" ON public.profiles AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((user_id = uid()) OR (id = uid()))) WITH CHECK (((user_id = uid()) OR (id = uid())));
