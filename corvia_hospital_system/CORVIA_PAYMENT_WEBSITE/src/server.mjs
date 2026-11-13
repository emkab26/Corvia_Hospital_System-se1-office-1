import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { loadConfig } from './config.mjs';
import { Database } from './db.mjs';
import { signature, equal, cents, paymentLink, validLink, checkoutFields, parseNotification, validSource, confirmNotification } from './payfast.mjs';
import * as views from './views.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const previewPlans = [
  { code: 'preview-monthly', name: 'Everyday care', description: 'An illustrative monthly healthcare access plan.', price_cents: 14900, billing_period: 'monthly' },
  { code: 'preview-yearly', name: 'A year of connection', description: 'An illustrative annual plan for connected care.', price_cents: 149900, billing_period: 'yearly' },
];
function fail(status, message) { const error = new Error(message); error.httpStatus = status; throw error; }
async function body(req, max = 32768) {
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > max) fail(413, 'Request too large'); chunks.push(chunk); }
  return Buffer.concat(chunks).toString('utf8');
}
function bearer(req) {
  const value = req.headers.authorization;
  if (!value?.startsWith('Bearer ') || value.length > 8192) fail(401, 'Sign in to Corvia first');
  return value.slice(7);
}
export function createServer(config, dependencies = {}) {
  const db = dependencies.db || new Database(config);
  const checkSource = dependencies.validSource || validSource;
  const confirm = dependencies.confirm || confirmNotification;
  const limits = new Map();
  function rateLimit(req) {
    // Socket-based throttling is conservative behind a proxy; edge rate limits are also recommended.
    const key = req.socket.remoteAddress; const now = Date.now();
    if (limits.size > 10000) for (const [k,v] of limits) if (v.until < now) limits.delete(k);
    let value = limits.get(key);
    if (!value || value.until < now) { value = { count: 0, until: now + 60000 }; limits.set(key, value); }
    if (++value.count > 30) fail(429, 'Too many attempts. Please wait a minute.');
  }
  async function attempt(token, input) {
    if (typeof input.plan_code !== 'string' || !input.plan_code || input.plan_code.length > 100) fail(400, 'Choose a valid plan');
    const key = input.idempotency_key || randomUUID();
    if (!uuid.test(key)) fail(400, 'Invalid checkout key');
    let user;
    try { user = await db.user(token); } catch { fail(401, 'Your session has expired. Please sign in again.'); }
    if (!user?.id || !user.email) fail(401, 'A Corvia account with an email address is required');
    const payment = await db.create(user, input.plan_code, key, config.environment);
    return { url: paymentLink(payment, config), payment_id: payment.id, environment: payment.environment };
  }
  async function signedPayment(id, query) {
    if (!uuid.test(id) || !validLink(id, query, config)) fail(403, 'This private payment link is invalid or expired. Check Billing in Corvia.');
    const payment = await db.payment(id);
    if (!payment || payment.environment !== config.environment) fail(404, 'Payment not found');
    return payment;
  }
  async function verifyStored(n, actor = null) {
    let valid;
    try { valid = await confirm(n.canonical_body, config); }
    catch {
      await db.rpc('corvia_payment_problem', { p_payment_id: n.payment_id, p_reason: 'provider_unavailable', p_actor: actor });
      fail(503, 'Provider verification is temporarily unavailable. Please retry.');
    }
    if (!valid) {
      await db.rpc('corvia_payment_problem', { p_payment_id: n.payment_id, p_reason: 'provider_rejected_notification', p_actor: actor });
      fail(422, 'Provider did not confirm this notification');
    }
    return db.rpc('corvia_apply_notification', { p_notification_id: n.id, p_actor: actor });
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Content-Security-Policy', `default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self'; form-action 'self' https://${config.payfastHost}; base-uri 'none'; frame-ancestors 'none'`);
    if (config.baseUrl.startsWith('https:')) res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    const send = (status, data, type = 'text/html; charset=utf-8') => { res.writeHead(status, { 'Content-Type': type }); res.end(data); };
    const json = (status, data) => send(status, JSON.stringify(data), 'application/json');
    let url;
    try {
      url = new URL(req.url, config.baseUrl);
      if (req.method === 'GET' && url.pathname === '/healthz') {
        // Read-only public health response; never permit cross-origin checkout.
        // Contains no credentials or customer data; Corvia may run at a different origin.
        res.setHeader('Access-Control-Allow-Origin', '*');
        return json(200, { app: 'corvia-payment-portal', status: 'ok', mode: config.preview ? 'preview' : config.environment });
      }
      if (req.method === 'GET' && /^\/assets\/(styles\.css|checkout\.js|payment-return\.js)$/.test(url.pathname)) {
        const file = await readFile(new URL(`../public${url.pathname}`, import.meta.url));
        return send(200, file, url.pathname.endsWith('.css') ? 'text/css' : 'text/javascript');
      }
      if (req.method === 'GET' && url.pathname === '/') return send(200, views.home(config.preview ? previewPlans : await db.plans(), config));
      if (config.preview) fail(503, 'Preview only. Configure the payment service to enable checkout.');
      if (req.method === 'POST' && url.pathname === '/api/checkout') {
        rateLimit(req);
        if (!req.headers['content-type']?.startsWith('application/json')) fail(415, 'JSON required');
        const token = bearer(req);
        let input; try { input = JSON.parse(await body(req)); } catch { fail(400, 'Invalid request'); }
        if (!input || typeof input !== 'object') fail(400, 'Invalid request');
        return json(200, await attempt(token, input));
      }
      if (req.method === 'POST' && url.pathname === '/checkout') {
        rateLimit(req);
        if (req.headers.origin !== config.baseUrl) fail(403, 'Open checkout from this website');
        if (!req.headers['content-type']?.startsWith('application/x-www-form-urlencoded')) fail(415, 'Form required');
        const input = Object.fromEntries(new URLSearchParams(await body(req)));
        let session;
        try { session = await db.login(input.email, input.password); }
        catch { return send(401, views.home(await db.plans(), config, 'Sign-in failed. Check your Corvia email and password.')); }
        const created = await attempt(session.access_token, input);
        res.writeHead(303, { Location: created.url }); return res.end();
      }
      const page = url.pathname.match(/^\/(checkout|return|cancel|receipt)\/([^/]+)$/);
      if (req.method === 'GET' && page) {
        const payment = await signedPayment(page[2], url.searchParams);
        if (page[1] === 'receipt') {
          if (payment.status !== 'paid') fail(409, 'Receipt available only after confirmed payment');
          return send(200, views.receipt(payment, config));
        }
        if (page[1] === 'checkout' && payment.status === 'pending') {
          // Status links last 24h; submitting an old checkout is limited to 30 minutes.
          if (Date.now() - Date.parse(payment.created_at) > 30 * 60000) fail(410, 'Checkout expired. Start a new payment from Billing or the plans page.');
          return send(200, views.checkout(payment, checkoutFields(payment, config), config));
        }
        return send(200, views.result(payment, config, page[1] === 'cancel'));
      }
      const status = url.pathname.match(/^\/api\/status\/([^/]+)$/);
      if (req.method === 'GET' && status) {
        const payment = await signedPayment(status[1], url.searchParams);
        return json(200, { status: payment.status, review_required: payment.review_required, environment: payment.environment });
      }
      if (req.method === 'POST' && url.pathname === '/payfast/itn') {
        if (!req.headers['content-type']?.startsWith('application/x-www-form-urlencoded')) fail(415, 'Form required');
        const raw = await body(req);
        let parsed; try { parsed = parseNotification(raw); } catch { fail(400, 'Invalid notification'); }
        const { entries, data, canonical } = parsed;
        if (!equal(signature(entries, config.passphrase, false), data.signature)) fail(400, 'Invalid signature');
        const ip = config.proxyHeader ? req.headers[config.proxyHeader] : req.socket.remoteAddress;
        if (typeof ip !== 'string' || ip.includes(',') || !await checkSource(ip)) fail(403, 'Invalid notification source');
        if (data.merchant_id !== config.merchantId || !uuid.test(data.m_payment_id || '') || !/^[\w-]{1,100}$/.test(data.pf_payment_id || '')) fail(400, 'Invalid merchant or reference');
        const payment = await db.payment(data.m_payment_id);
        if (!payment || payment.environment !== config.environment) fail(404, 'Unknown payment');
        let amount; try { amount = cents(data.amount_gross); } catch { amount = -1; }
        if (amount !== Number(payment.amount_cents)) {
          await db.rpc('corvia_payment_problem', { p_payment_id: payment.id, p_reason: 'amount_mismatch' });
          fail(422, 'Amount mismatch');
        }
        const id = await db.rpc('corvia_record_notification', {
          p_payment_id: payment.id, p_digest: createHash('sha256').update(raw).digest('hex'),
          p_raw: raw, p_canonical: canonical, p_provider_id: data.pf_payment_id,
          p_status: data.payment_status || '', p_source_ip: ip,
        });
        await verifyStored({ id, payment_id: payment.id, canonical_body: canonical });
        return send(200, 'OK', 'text/plain');
      }
      const privateLink = url.pathname.match(/^\/api\/payment-link\/([^/]+)$/);
      if (req.method === 'POST' && privateLink) {
        rateLimit(req); const token = bearer(req);
        if (!uuid.test(privateLink[1])) fail(400, 'Invalid payment');
        const user = await db.user(token);
        const payment = await db.payment(privateLink[1]);
        if (!payment || (payment.user_id !== user.id && !await db.rpc('corvia_payment_staff', { p_hospital_id: payment.hospital_id }, token))) fail(403, 'Payment access denied');
        if (payment.environment !== config.environment) fail(409, 'Payment belongs to another environment');
        // Issue a fresh status/receipt link; never revive an expired checkout.
        const link = paymentLink({ ...payment, created_at: new Date().toISOString() }, config);
        return json(200, { url: link.replace('/checkout/', payment.status === 'paid' ? '/receipt/' : '/return/') });
      }
      const reconcile = url.pathname.match(/^\/api\/reconcile\/([^/]+)$/);
      if (req.method === 'POST' && reconcile) {
        rateLimit(req); const token = bearer(req);
        if (!uuid.test(reconcile[1])) fail(400, 'Invalid payment');
        const user = await db.user(token);
        const payment = await db.payment(reconcile[1]);
        if (!payment || !await db.rpc('corvia_payment_staff', { p_hospital_id: payment.hospital_id }, token)) fail(403, 'Billing staff access required');
        if (payment.environment !== config.environment) fail(409, 'Payment belongs to another environment');
        const notifications = await db.request(`/rest/v1/corvia_payment_notifications?payment_id=eq.${payment.id}&order=created_at.asc`, { service: true });
        if (!notifications.length) {
          await db.rpc('corvia_payment_problem', { p_payment_id: payment.id, p_reason: 'no_notification_request_payfast_itn_resend', p_actor: user.id });
          return json(200, { message: 'No signed notification received. Request an ITN resend in the PayFast merchant dashboard; status remains unconfirmed.' });
        }
        for (const n of notifications) await verifyStored(n, user.id);
        return json(200, { message: 'Stored notifications checked with PayFast. Refresh the ledger for the result.' });
      }
      fail(404, 'Page not found');
    } catch (error) {
      const code = error.httpStatus || 503;
      const message = error.httpStatus ? error.message : 'Payment service unavailable. Please retry later or contact your billing team.';
      // Log only classification, never request bodies/URLs (private links), credentials or raw provider data.
      if (!error.httpStatus) console.error('payment_service_error', { status: error.status || 503 });
      if (url?.pathname.startsWith('/api/') || url?.pathname === '/payfast/itn') return json(code, { error: message });
      return send(code, views.layout('Payment service', `<section class="narrow panel"><h1>We could not continue</h1><p role="alert">${views.escape(message)}</p><a href="/">Back to plans</a></section>`, config));
    }
  });
  server.requestTimeout = 20000; server.headersTimeout = 15000;
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = loadConfig();
  createServer(config).listen(config.port, config.host, () => console.log(`Corvia payment portal listening on ${config.host}:${config.port} (${config.environment})`));
}
