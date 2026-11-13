-- Read-only verification after all three Corvia PayFast migrations.
select
  to_regclass('public.corvia_payment_attempts') is not null as payment_attempts,
  to_regclass('public.corvia_payment_notifications') is not null as notifications,
  to_regclass('public.corvia_payment_entitlements') is not null as entitlements,
  to_regclass('public.corvia_existing_account_access') is not null as existing_access,
  to_regprocedure('public.corvia_create_payment(uuid,text,text,uuid,text)') is not null as create_rpc,
  to_regprocedure('public.corvia_apply_notification(uuid,uuid)') is not null as apply_rpc,
  to_regprocedure('public.corvia_account_access()') is not null as access_rpc,
  to_regprocedure('public.corvia_hospital_payment_totals(uuid)') is not null as billing_totals_rpc;

select captured_at as existing_account_cutoff
from public.corvia_access_rollout
where singleton;

select count(*) as grandfathered_accounts
from public.corvia_existing_account_access;

select
  environment,
  count(*) filter (where status = 'paid') as confirmed_payments,
  coalesce(sum(amount_cents) filter (where status = 'paid'), 0) as confirmed_amount_cents,
  count(*) filter (where status = 'pending') as pending_payments,
  count(*) filter (where review_required) as review_required
from public.corvia_payment_attempts
group by environment
order by environment;
