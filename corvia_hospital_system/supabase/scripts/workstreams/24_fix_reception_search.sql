-- Reception "Search Patient" returned nothing (13 Oct 2026).
--
-- The live function matched each column on its own, so a full name such as
-- "Alice Brown" never matched; it read names only from profiles (inner join),
-- and only matched patients.hospital_id, ignoring patient_hospital_links.
-- Same name, arguments, return columns and SECURITY DEFINER as before, so the
-- Flutter app needs no change.

create or replace function public.reception_search_patients(p_search text)
returns table(
  patient_id uuid,
  patient_number text,
  first_name text,
  surname text,
  phone_number text,
  date_of_birth date
)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  current_hospital_id uuid;
  search_text text;
begin
  current_hospital_id := public.reception_current_hospital_id();
  search_text := lower(trim(coalesce(p_search, '')));

  if current_hospital_id is null or length(search_text) < 2 then
    return;
  end if;

  return query
  with candidates as (
    select
      p.id,
      p.patient_number,
      coalesce(nullif(trim(p.first_name), ''), nullif(trim(pr.first_name), ''), '') as first_name,
      coalesce(nullif(trim(p.surname), ''), nullif(trim(pr.surname), ''), '') as surname,
      coalesce(nullif(trim(p.phone), ''), pr.phone_number, pr.phone, '') as phone,
      coalesce(pr.id_number, '') as id_number,
      coalesce(p.email, pr.email, '') as email,
      coalesce(p.date_of_birth, pr.date_of_birth) as date_of_birth
    from public.patients p
    left join public.profiles pr on pr.user_id = p.profile_id
    where coalesce(p.is_active, true)
      and (
        p.hospital_id = current_hospital_id
        or exists (
          select 1
          from public.patient_hospital_links l
          where l.patient_id = p.id
            and l.hospital_id = current_hospital_id
            and l.status = 'active'
        )
      )
  )
  select
    c.id,
    coalesce(c.patient_number, 'No patient number'),
    c.first_name,
    c.surname,
    c.phone,
    c.date_of_birth
  from candidates c
  where lower(c.first_name || ' ' || c.surname) like '%' || search_text || '%'
     or lower(c.surname || ' ' || c.first_name) like '%' || search_text || '%'
     or lower(coalesce(c.patient_number, '')) like '%' || search_text || '%'
     or lower(c.id_number) like '%' || search_text || '%'
     or regexp_replace(c.phone, '\D', '', 'g')
          like '%' || nullif(regexp_replace(search_text, '\D', '', 'g'), '') || '%'
     or lower(c.email) like '%' || search_text || '%'
  order by c.first_name, c.surname
  limit 30;
end;
$function$;

notify pgrst, 'reload schema';
