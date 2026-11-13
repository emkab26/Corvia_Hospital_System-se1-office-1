-- Additive payment ledger. Apply to the TEST database first.
-- Existing pricing_plans/profiles/patients/hospital_admins/subscriptions remain intact.
begin;

create table public.corvia_payment_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  hospital_id uuid,
  email text not null,
  plan_code text not null,
  plan_name text not null,
  billing_period text not null,
  amount_cents bigint not null check (amount_cents between 500 and 999999999),
  currency text not null default 'ZAR' check (currency = 'ZAR'),
  environment text not null check (environment in ('sandbox','live')),
  idempotency_key uuid not null,
  status text not null default 'pending' check (status in ('pending','paid','failed','cancelled')),
  provider_payment_id text,
  reason_code text,
  review_required boolean not null default false,
  duplicate_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_checked_at timestamptz,
  paid_at timestamptz,
  unique(user_id, idempotency_key),
  unique(environment, provider_payment_id)
);
create index corvia_payment_queue on public.corvia_payment_attempts(hospital_id, created_at desc);
create index corvia_payment_customer on public.corvia_payment_attempts(user_id, created_at desc);

create table public.corvia_payment_notifications (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.corvia_payment_attempts(id),
  digest text not null unique,
  raw_body text not null,
  canonical_body text not null,
  provider_payment_id text not null,
  provider_status text not null,
  source_ip text not null,
  state text not null default 'received' check (state in ('received','verified','rejected')),
  created_at timestamptz not null default now(),
  verified_at timestamptz
);

create table public.corvia_payment_events (
  id bigint generated always as identity primary key,
  payment_id uuid not null references public.corvia_payment_attempts(id),
  actor_id uuid,
  event_type text not null,
  detail text not null,
  created_at timestamptz not null default now()
);

create table public.corvia_payment_receipts (
  payment_id uuid primary key references public.corvia_payment_attempts(id),
  receipt_number text not null unique,
  created_at timestamptz not null default now()
);

create table public.corvia_payment_entitlements (
  payment_id uuid primary key references public.corvia_payment_attempts(id),
  user_id uuid not null references auth.users(id),
  environment text not null,
  plan_code text not null,
  valid_from timestamptz not null,
  valid_until timestamptz not null
);

-- Sandbox must never silently grant access on a production database.
create table public.corvia_payment_settings (
  singleton boolean primary key default true check(singleton),
  allow_sandbox_access boolean not null default false
);
insert into public.corvia_payment_settings default values;

create function public.corvia_payment_staff(p_hospital_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.hospital_admins a
    join public.profiles p on p.id = a.profile_id or p.user_id = a.profile_id
    where a.hospital_id = p_hospital_id
      and (a.profile_id = auth.uid() or p.user_id = auth.uid())
      and coalesce((to_jsonb(p)->>'is_active')::boolean, true)
  ) or exists (
    select 1 from public.profiles p where (p.id = auth.uid() or p.user_id = auth.uid())
      and lower(to_jsonb(p)->>'user_type') = 'admin'
      and coalesce((to_jsonb(p)->>'is_active')::boolean, true)
  );
$$;

alter table public.corvia_payment_attempts enable row level security;
alter table public.corvia_payment_notifications enable row level security;
alter table public.corvia_payment_events enable row level security;
alter table public.corvia_payment_receipts enable row level security;
alter table public.corvia_payment_entitlements enable row level security;
alter table public.corvia_payment_settings enable row level security;

create policy payment_read on public.corvia_payment_attempts for select to authenticated
  using (user_id = auth.uid() or public.corvia_payment_staff(hospital_id));
create policy payment_event_read on public.corvia_payment_events for select to authenticated
  using (exists(select 1 from public.corvia_payment_attempts a where a.id = payment_id));
create policy payment_receipt_read on public.corvia_payment_receipts for select to authenticated
  using (exists(select 1 from public.corvia_payment_attempts a where a.id = payment_id));
create policy payment_entitlement_read on public.corvia_payment_entitlements for select to authenticated
  using (user_id = auth.uid());

revoke all on public.corvia_payment_attempts, public.corvia_payment_notifications,
  public.corvia_payment_events, public.corvia_payment_receipts,
  public.corvia_payment_entitlements, public.corvia_payment_settings from anon, authenticated;
-- Keep customer email and idempotency keys out of client ledger responses.
grant select(id,user_id,hospital_id,plan_code,plan_name,billing_period,amount_cents,currency,
  environment,status,provider_payment_id,reason_code,review_required,duplicate_count,
  created_at,updated_at,last_checked_at,paid_at) on public.corvia_payment_attempts to authenticated;
grant select on public.corvia_payment_events, public.corvia_payment_receipts,
  public.corvia_payment_entitlements to authenticated;
grant all on public.corvia_payment_attempts, public.corvia_payment_notifications,
  public.corvia_payment_events, public.corvia_payment_receipts,
  public.corvia_payment_entitlements, public.corvia_payment_settings to service_role;
grant usage, select on sequence public.corvia_payment_events_id_seq to service_role;

create function public.corvia_create_payment(p_user_id uuid, p_email text, p_plan_code text,
  p_idempotency_key uuid, p_environment text) returns public.corvia_payment_attempts
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.corvia_payment_attempts; plan jsonb; hospital uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  select * into a from public.corvia_payment_attempts where user_id=p_user_id and idempotency_key=p_idempotency_key;
  if found then
    if a.plan_code <> p_plan_code or a.environment <> p_environment then raise exception 'Idempotency key already used'; end if;
    return a;
  end if;
  if (select count(*) from public.corvia_payment_attempts where user_id=p_user_id and created_at > now()-interval '1 minute') >= 5 then
    raise exception 'Too many attempts; wait a minute';
  end if;
  if p_email is null or length(p_email) > 100 then raise exception 'An account email is required'; end if;
  select to_jsonb(p) into plan from public.pricing_plans p where p.code=p_plan_code and p.is_active=true;
  if plan is null or plan->>'currency' <> 'ZAR' then raise exception 'Plan unavailable'; end if;
  select pt.hospital_id into hospital from public.patients pt
    where pt.profile_id=p_user_id or pt.profile_id in (select pr.id from public.profiles pr where pr.user_id=p_user_id)
    order by pt.id limit 1;
  insert into public.corvia_payment_attempts(user_id,hospital_id,email,plan_code,plan_name,billing_period,amount_cents,environment,idempotency_key)
    values(p_user_id,hospital,p_email,p_plan_code,plan->>'name',coalesce(plan->>'billing_period','one_off'),
      (plan->>'price_cents')::bigint,p_environment,p_idempotency_key) returning * into a;
  insert into public.corvia_payment_events(payment_id,actor_id,event_type,detail)
    values(a.id,p_user_id,'created','Checkout created from server-side catalogue');
  return a;
end;
$$;

-- Only the portal service calls this after validating signature, source and amount.
create function public.corvia_record_notification(p_payment_id uuid,p_digest text,p_raw text,p_canonical text,
  p_provider_id text,p_status text,p_source_ip text) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
  perform 1 from public.corvia_payment_attempts where id=p_payment_id for update;
  select id into result from public.corvia_payment_notifications where digest=p_digest;
  if found then
    update public.corvia_payment_attempts set duplicate_count=duplicate_count+1 where id=p_payment_id;
    insert into public.corvia_payment_events(payment_id,event_type,detail) values(p_payment_id,'duplicate','Repeated signed provider notification');
    return result;
  end if;
  insert into public.corvia_payment_notifications(payment_id,digest,raw_body,canonical_body,provider_payment_id,provider_status,source_ip)
    values(p_payment_id,p_digest,p_raw,p_canonical,p_provider_id,p_status,p_source_ip) returning id into result;
  insert into public.corvia_payment_events(payment_id,event_type,detail) values(p_payment_id,'notification_received','Signed source-checked notification stored; server confirmation pending');
  return result;
end;
$$;

create function public.corvia_payment_problem(p_payment_id uuid,p_reason text,p_actor uuid default null) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.corvia_payment_attempts set review_required=true,reason_code=left(p_reason,120),
    last_checked_at=now(),updated_at=now() where id=p_payment_id;
  insert into public.corvia_payment_events(payment_id,actor_id,event_type,detail)
    values(p_payment_id,p_actor,'review_required',left(p_reason,120));
end;
$$;

create function public.corvia_apply_notification(p_notification_id uuid,p_actor uuid default null) returns text
language plpgsql security definer set search_path=public,pg_temp as $$
declare n public.corvia_payment_notifications; a public.corvia_payment_attempts; next_status text; start_at timestamptz; period interval;
begin
  select * into n from public.corvia_payment_notifications where id=p_notification_id;
  if not found then raise exception 'Unknown notification'; end if;
  -- Serialize purchases for one account, then payment; always acquire in this order.
  select * into a from public.corvia_payment_attempts where id=n.payment_id;
  perform pg_advisory_xact_lock(hashtextextended(a.user_id::text,0));
  select * into a from public.corvia_payment_attempts where id=n.payment_id for update;
  select * into n from public.corvia_payment_notifications where id=p_notification_id for update;
  if n.state='verified' then return a.status; end if;
  if a.provider_payment_id is not null and a.provider_payment_id <> n.provider_payment_id then
    perform public.corvia_payment_problem(a.id,'provider_reference_conflict',p_actor); return a.status;
  end if;
  if exists(select 1 from public.corvia_payment_attempts where environment=a.environment and provider_payment_id=n.provider_payment_id and id<>a.id) then
    perform public.corvia_payment_problem(a.id,'provider_reference_reused',p_actor); return a.status;
  end if;
  next_status := case n.provider_status when 'COMPLETE' then 'paid' when 'CANCELLED' then 'cancelled' when 'FAILED' then 'failed' else null end;
  if next_status is null then
    perform public.corvia_payment_problem(a.id,'unsupported_provider_status',p_actor); return a.status;
  end if;
  -- Final success never regresses because of late cancellation/failure.
  if a.status='paid' and next_status<>'paid' then
    perform public.corvia_payment_problem(a.id,'conflicting_final_state',p_actor); return a.status;
  end if;
  update public.corvia_payment_notifications set state='verified',verified_at=now() where id=n.id;
  update public.corvia_payment_attempts set status=next_status,provider_payment_id=n.provider_payment_id,
    paid_at=case when next_status='paid' then coalesce(paid_at,now()) else paid_at end,
    last_checked_at=now(),updated_at=now(),review_required=false,reason_code=null where id=a.id;
  insert into public.corvia_payment_events(payment_id,actor_id,event_type,detail)
    values(a.id,p_actor,'provider_verified',a.status || ' -> ' || next_status);
  if next_status='paid' then
    insert into public.corvia_payment_receipts(payment_id,receipt_number)
      values(a.id,'COR-' || upper(a.id::text)) on conflict do nothing;
    period := case a.billing_period when 'monthly' then interval '1 month' when 'yearly' then interval '1 year' else null end;
    if period is not null and not exists(select 1 from public.corvia_payment_entitlements where payment_id=a.id) then
      select greatest(now(),coalesce(max(valid_until),now())) into start_at from public.corvia_payment_entitlements
        where user_id=a.user_id and environment=a.environment and plan_code=a.plan_code;
      insert into public.corvia_payment_entitlements(payment_id,user_id,environment,plan_code,valid_from,valid_until)
        values(a.id,a.user_id,a.environment,a.plan_code,start_at,start_at+period) on conflict do nothing;
    end if;
  end if;
  return next_status;
end;
$$;

create function public.corvia_payment_access() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.corvia_payment_entitlements e
    where e.user_id=auth.uid() and e.valid_from<=now() and e.valid_until>now()
    and (e.environment='live' or (select allow_sandbox_access from public.corvia_payment_settings where singleton)));
$$;

-- Mutation functions are service-only; browser/mobile users can never mark an attempt paid.
revoke all on function public.corvia_create_payment(uuid,text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.corvia_record_notification(uuid,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.corvia_apply_notification(uuid,uuid) from public,anon,authenticated;
revoke all on function public.corvia_payment_problem(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.corvia_create_payment(uuid,text,text,uuid,text),
  public.corvia_record_notification(uuid,text,text,text,text,text,text),
  public.corvia_apply_notification(uuid,uuid),public.corvia_payment_problem(uuid,text,uuid) to service_role;
revoke all on function public.corvia_payment_staff(uuid),public.corvia_payment_access() from public,anon;
grant execute on function public.corvia_payment_staff(uuid),public.corvia_payment_access() to authenticated,service_role;
commit;
