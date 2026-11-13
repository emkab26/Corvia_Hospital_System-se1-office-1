-- Run after the blood-bank base/workspace migrations. Safe to repeat.
-- Search by patient name/number or exact recorded ID number; UUIDs stay internal.
begin;
set local lock_timeout = '10s';

create or replace function public.corvia_bb_patient_options(p_hospital_id uuid,p_search text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_search text := lower(trim(p_search));
begin
  if coalesce(corvia_bb_private.member_role(p_hospital_id),'') not in ('manager','clinician') then
    raise exception 'Patient search denied' using errcode='42501';
  end if;
  if v_search is null or length(v_search)<2 then return '[]'::jsonb; end if;
  if length(p_search)>100 then raise exception 'Search too long'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(r) order by r.patient_number,r.id),'[]'::jsonb)
    from (
      select p.id,p.patient_number,
        coalesce(
          nullif(trim(concat_ws(' ',p.first_name,p.surname)),''),
          nullif(trim(concat_ws(' ',pr.first_name,pr.surname)),''),
          'Name not recorded'
        ) as patient_name
      from public.patients p
      left join public.profiles pr on pr.user_id=p.profile_id
      where p.hospital_id=p_hospital_id and p.is_active is true
        and (
          position(v_search in lower(concat_ws(' ',p.patient_number,p.first_name,p.surname)))>0
          or position(v_search in lower(concat_ws(' ',pr.first_name,pr.surname)))>0
          or lower(trim(pr.id_number))=v_search
        )
      order by p.patient_number,p.id limit 25
    ) r
  );
end $$;

revoke all on function public.corvia_bb_patient_options(uuid,text) from public,anon,service_role;
grant execute on function public.corvia_bb_patient_options(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
