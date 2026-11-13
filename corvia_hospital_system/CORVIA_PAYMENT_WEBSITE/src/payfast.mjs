import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { resolve4 } from 'node:dns/promises';
import { BlockList } from 'node:net';

// PHP urlencode, required by PayFast (including tilde and punctuation).
export const encode = value => encodeURIComponent(String(value)).replace(/[!'()*~]/g, c => `%${c.charCodeAt(0).toString(16).toUpperCase()}`).replace(/%20/g, '+');
export const parameterString = (entries, skipBlank = false) => entries.filter(([k, v]) => k !== 'signature' && (!skipBlank || String(v).trim() !== '')).map(([k, v]) => `${k}=${encode(skipBlank ? String(v).trim() : v)}`).join('&');
export function signature(entries, passphrase, skipBlank = true) {
  return createHash('md5').update(parameterString(entries, skipBlank) + (passphrase ? `&passphrase=${encode(passphrase)}` : '')).digest('hex');
}
export function equal(a, b) {
  return typeof a === 'string' && typeof b === 'string' && Buffer.byteLength(a) === Buffer.byteLength(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
export function cents(value) {
  if (!/^\d{1,10}\.\d{2}$/.test(String(value))) throw new Error('Invalid amount');
  const [whole, fraction] = String(value).split('.');
  return Number(whole) * 100 + Number(fraction);
}
export function paymentLink(payment, config) {
  const expiry = Math.floor(new Date(payment.created_at).getTime() / 1000) + 86400;
  const token = createHmac('sha256', config.linkSecret).update(`${payment.id}.${expiry}`).digest('hex');
  return `${config.baseUrl}/checkout/${payment.id}?expires=${expiry}&token=${token}`;
}
export function validLink(id, query, config, now = Date.now()) {
  const expiry = query.get('expires');
  if (!/^\d{10}$/.test(expiry || '') || Number(expiry) * 1000 <= now) return false;
  const expected = createHmac('sha256', config.linkSecret).update(`${id}.${expiry}`).digest('hex');
  return equal(expected, query.get('token'));
}
export function checkoutFields(payment, config) {
  const link = paymentLink(payment, config);
  const fields = [
    ['merchant_id', config.merchantId], ['merchant_key', config.merchantKey],
    ['return_url', link.replace('/checkout/', '/return/')],
    ['cancel_url', link.replace('/checkout/', '/cancel/')],
    ['notify_url', `${config.baseUrl}/payfast/itn`],
    ['email_address', payment.email], ['m_payment_id', payment.id],
    ['amount', (payment.amount_cents / 100).toFixed(2)], ['item_name', payment.plan_name.slice(0, 100)],
    ['item_description', 'Single payment for the selected access period. No automatic renewal.'],
  ];
  return [...fields, ['signature', signature(fields, config.passphrase)]];
}
export function parseNotification(raw) {
  const entries = [...new URLSearchParams(raw)];
  const keys = entries.map(([k]) => k);
  if (new Set(keys).size !== keys.length || keys.at(-1) !== 'signature') throw new Error('Duplicate fields or signature not last');
  return { entries, data: Object.fromEntries(entries), canonical: parameterString(entries) };
}
export async function validSource(ip, resolver = resolve4) {
  const source = String(ip || '').replace(/^::ffff:/, '');
  const allowed = new BlockList();
  // Published PayFast ranges, checked 7 October 2026; DNS supplements these.
  for (const [address, prefix] of [['197.97.145.144', 28], ['41.74.179.192', 27], ['102.216.36.0', 28], ['102.216.36.128', 28]]) allowed.addSubnet(address, prefix);
  allowed.addAddress('144.126.193.139');
  if (allowed.check(source, 'ipv4')) return true;
  const hosts = ['www.payfast.co.za', 'w1w.payfast.co.za', 'w2w.payfast.co.za', 'sandbox.payfast.co.za'];
  const resolved = await Promise.allSettled(hosts.map(host => resolver(host)));
  return resolved.some(result => result.status === 'fulfilled' && result.value.includes(source));
}
export async function confirmNotification(canonical, config, fetcher = fetch) {
  const response = await fetcher(`https://${config.payfastHost}/eng/query/validate`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: canonical, signal: AbortSignal.timeout(15000), redirect: 'error',
  });
  if (!response.ok) throw new Error('Provider confirmation unavailable');
  return (await response.text()).trim() === 'VALID';
}
