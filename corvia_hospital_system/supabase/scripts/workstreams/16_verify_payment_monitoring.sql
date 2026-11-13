-- Read-only WS3 Payment Monitoring verification.
-- Run in Supabase SQL Editor before testing the Flutter Billing pages.
select
  to_regclass('public.corvia_payment_attempts') is not null
    as payment_attempts_installed,
  to_regclass('public.corvia_payment_receipts') is not null
    as payment_receipts_installed,
  to_regclass('public.corvia_payment_entitlements') is not null
    as payment_entitlements_installed,
  to_regclass('public.corvia_payment_reviews') is not null
    as payment_reviews_installed,
  to_regprocedure('public.corvia_payment_staff(uuid)') is not null
    as payment_staff_check_installed,
  to_regprocedure('public.corvia_payment_access()') is not null
    as payment_access_check_installed,
  to_regprocedure(
    'public.corvia_payment_escalate(uuid,text,boolean)'
  ) is not null as payment_review_rpc_installed;

-- Aggregate rows only; no patient/payment detail is returned.
select
  count(*) as attempts,
  count(*) filter (where status = 'pending') as pending,
  count(*) filter (where status = 'paid') as paid,
  count(*) filter (where review_required) as requiring_review,
  coalesce(sum(duplicate_count), 0) as duplicate_notifications
from public.corvia_payment_attempts;
