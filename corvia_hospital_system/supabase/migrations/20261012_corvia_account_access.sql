-- Account rollout and hospital billing totals.
-- Apply after 20261006_corvia_payfast_portal.sql and 20261009_corvia_payment_escalation.sql.
-- The first successful execution captures all auth users that already exist.
begin;

create table if not exists public.corvia_access_rollout (
  singleton boolean primary key default true check (singleton),
  captured_at timestamptz not null default now()
);
insert into public.corvia_access_rollout(singleton) values (true)
on conflict (singleton) do nothing;

create table if not exists public.corvia_existing_account_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  grandfathered_at timestamptz not null default now()
);

insert into public.corvia_existing_account_access(user_id)
select u.id
from auth.users u
cross join public.corvia_access_rollout r
where r.singleton and u.created_at <= r.captured_at
on conflict (user_id) do nothing;

alter table public.corvia_existing_account_access enable row level security;
revoke all on public.corvia_access_rollout, public.corvia_existing_account_access
  from public, anon, authenticated;
grant all on public.corvia_access_rollout, public.corvia_existing_account_access to service_role;

create or replace function public.corvia_payment_access() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select
    exists (
      select 1 from public.corvia_existing_account_access x
      where x.user_id = auth.uid()
    )
    or exists (
      select 1 from public.corvia_payment_entitlements e
      where e.user_id = auth.uid()
        and e.valid_from <= now()
        and e.valid_until > now()
        and (
          e.environment = 'live'
          or (
            e.environment = 'sandbox'
            and coalesce((
              select s.allow_sandbox_access
              from public.corvia_payment_settings s
              where s.singleton
            ), false)
          )
        )
    );
$$;

create or replace function public.corvia_account_access()
returns table (
  access_tier text,
  has_full_access boolean,
  access_source text,
  valid_until timestamptz
)
language sql stable security definer set search_path=public,pg_temp as $$
  with state as (
    select
      exists (
        select 1 from public.corvia_existing_account_access x
        where x.user_id = auth.uid()
      ) as grandfathered,
      (
        select max(e.valid_until)
        from public.corvia_payment_entitlements e
        where e.user_id = auth.uid()
          and e.valid_from <= now()
          and e.valid_until > now()
          and (
            e.environment = 'live'
            or (
              e.environment = 'sandbox'
              and coalesce((select s.allow_sandbox_access from public.corvia_payment_settings s where s.singleton), false)
            )
          )
      ) as paid_until
  )
  select
    case when grandfathered or paid_until is not null then 'full' else 'free' end,
    grandfathered or paid_until is not null,
    case when grandfathered then 'existing_account'
         when paid_until is not null then 'confirmed_payment'
         else 'new_account_free' end,
    paid_until
  from state;
$$;

create or replace function public.corvia_hospital_payment_totals(p_hospital_id uuid)
returns table (
  environment text,
  confirmed_payments bigint,
  confirmed_amount_cents bigint,
  pending_payments bigint,
  review_required bigint
)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or not public.corvia_payment_staff(p_hospital_id) then
    raise exception 'Billing staff access required';
  end if;
  return query
  select
    a.environment,
    count(*) filter (where a.status = 'paid')::bigint,
    coalesce(sum(a.amount_cents) filter (where a.status = 'paid'), 0)::bigint,
    count(*) filter (where a.status = 'pending')::bigint,
    count(*) filter (where a.review_required)::bigint
  from public.corvia_payment_attempts a
  where a.hospital_id = p_hospital_id
  group by a.environment
  order by a.environment;
end;
$$;

revoke all on function public.corvia_payment_access() from public,anon;
revoke all on function public.corvia_account_access() from public,anon;
revoke all on function public.corvia_hospital_payment_totals(uuid) from public,anon;
grant execute on function public.corvia_payment_access(), public.corvia_account_access(),
  public.corvia_hospital_payment_totals(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
