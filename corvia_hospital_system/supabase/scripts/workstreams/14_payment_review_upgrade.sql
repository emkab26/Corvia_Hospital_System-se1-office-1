-- Apply after 20261006_corvia_payfast_portal.sql. Never changes provider payment state.
begin;
create table if not exists public.corvia_payment_reviews (
 payment_id uuid primary key references public.corvia_payment_attempts(id),
 reason text not null check(length(trim(reason)) between 5 and 1000),
 raised_by uuid not null, raised_at timestamptz not null default now(),
 state text not null default 'open' check(state in ('open','resolved')),
 resolved_by uuid,resolved_at timestamptz,resolution text
);
alter table public.corvia_payment_reviews enable row level security;
revoke all on public.corvia_payment_reviews from public,anon,authenticated;
grant select on public.corvia_payment_reviews to authenticated;
drop policy if exists payment_review_staff_read on public.corvia_payment_reviews;
create policy payment_review_staff_read on public.corvia_payment_reviews for select to authenticated
 using(exists(select 1 from public.corvia_payment_attempts a where a.id=payment_id and public.corvia_payment_staff(a.hospital_id)));
create or replace function public.corvia_payment_escalate(p_payment_id uuid,p_reason text,p_resolve boolean default false) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.corvia_payment_attempts%rowtype; existing public.corvia_payment_reviews%rowtype;
begin
 select * into a from public.corvia_payment_attempts where id=p_payment_id for update;
 if auth.uid() is null or not found or not public.corvia_payment_staff(a.hospital_id) then raise exception 'Billing staff access required';end if;
 if coalesce(length(trim(p_reason)),0) not between 5 and 1000 then raise exception 'Enter a reason between 5 and 1000 characters';end if;
 select * into existing from public.corvia_payment_reviews where payment_id=p_payment_id;
 if p_resolve then
  if existing.payment_id is null then raise exception 'No review exists';end if;
  if existing.state='resolved' and existing.resolution=p_reason then return;end if;
  if existing.state='resolved' then raise exception 'This review is already resolved';end if;
  update public.corvia_payment_reviews set state='resolved',resolved_by=auth.uid(),resolved_at=now(),resolution=p_reason where payment_id=p_payment_id;
 else
  if existing.state='open' and existing.reason=p_reason then return;end if;
  insert into public.corvia_payment_reviews(payment_id,reason,raised_by) values(p_payment_id,p_reason,auth.uid())
  on conflict(payment_id) do update set reason=excluded.reason,raised_by=excluded.raised_by,raised_at=now(),state='open',resolved_by=null,resolved_at=null,resolution=null;
 end if;
 insert into public.corvia_payment_events(payment_id,actor_id,event_type,detail)
 values(p_payment_id,auth.uid(),case when p_resolve then 'staff_review_resolved' else 'staff_review_raised' end,
 case when p_resolve then 'Billing review resolved: ' else 'Billing review requested: ' end || p_reason);
end $$;
revoke all on function public.corvia_payment_escalate(uuid,text,boolean) from public,anon;
grant execute on function public.corvia_payment_escalate(uuid,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
