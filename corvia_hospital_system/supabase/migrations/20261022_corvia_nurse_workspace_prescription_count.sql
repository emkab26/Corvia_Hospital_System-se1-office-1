-- Apply after 20261022_corvia_nurse_workspace.sql.
-- A nurse-scoped count avoids mistaking RLS-filtered client reads for zero.
begin;

create or replace function public.corvia_nurse_active_prescription_count_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_workspace jsonb;
  v_count bigint;
begin
  -- Reuse the workspace's authenticated nurse/hospital authorization and its
  -- current active assignments. No caller-supplied patient IDs are accepted.
  v_workspace := public.corvia_nurse_workspace_v1();

  select count(*) into v_count
  from public.prescriptions prescription
  where prescription.status = 'active'
    and exists (
      select 1
      from jsonb_array_elements(v_workspace->'assignments') assignment
      where (assignment->>'patient_id')::uuid = prescription.patient_id
    );

  return jsonb_build_object(
    'hospital_id', v_workspace->'context'->>'hospital_id',
    'nurse_user_id', v_workspace->'context'->>'nurse_user_id',
    'active_prescriptions', v_count
  );
end;
$function$;

revoke all on function public.corvia_nurse_active_prescription_count_v1() from public, anon;
grant execute on function public.corvia_nurse_active_prescription_count_v1() to authenticated;

notify pgrst, 'reload schema';
commit;
