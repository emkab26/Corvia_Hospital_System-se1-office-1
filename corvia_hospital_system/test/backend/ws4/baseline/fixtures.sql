-- Synthetic test data only. No real account, contact, location or patient data.
INSERT INTO auth.users(id)
SELECT ('00000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid
FROM generate_series(1,9) n;

INSERT INTO public.profiles(user_id,id,first_name,role,user_type,is_active)
SELECT id, gen_random_uuid(), 'Synthetic ' || right(id::text,1),
 CASE right(id::text,1)
 WHEN '3' THEN 'dispatcher' WHEN '4' THEN 'dispatcher'
 WHEN '5' THEN 'dispatch_supervisor' WHEN '6' THEN 'dispatcher'
 WHEN '7' THEN 'doctor' ELSE 'patient' END,
 'patient', right(id::text,1) <> '6'
FROM auth.users WHERE right(id::text,1) NOT IN ('8','9');

INSERT INTO public.incidents(id,user_id,latitude,longitude,status)
OVERRIDING SYSTEM VALUE VALUES
 (101,'00000000-0000-4000-8000-000000000001',-30,25,'pending'),
 (102,'00000000-0000-4000-8000-000000000002',-30,25,'pending'),
 (103,'00000000-0000-4000-8000-000000000001',-30,25,'resolved'),
 (104,'00000000-0000-4000-8000-000000000001',-30,25,'cancelled'),
 (105,'00000000-0000-4000-8000-000000000001',-30,25,NULL),
 (106,'00000000-0000-4000-8000-000000000001',-30,25,'unrecognised');
SELECT setval(pg_get_serial_sequence('public.incidents','id'),106);

-- Proposed scope labels for tests only. Current production contract has no
-- organization/routing field; these labels are NOT read by the baseline policy.
CREATE SCHEMA ws4_fixture;
CREATE TABLE ws4_fixture.coverage (user_id uuid PRIMARY KEY, organization text);
INSERT INTO ws4_fixture.coverage VALUES
 ('00000000-0000-4000-8000-000000000001','synthetic-a'),
 ('00000000-0000-4000-8000-000000000002','synthetic-b'),
 ('00000000-0000-4000-8000-000000000003','synthetic-a'),
 ('00000000-0000-4000-8000-000000000004','synthetic-b');
