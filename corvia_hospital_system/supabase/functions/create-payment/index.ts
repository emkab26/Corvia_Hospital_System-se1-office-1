// Compatibility adapter for the existing Flutter `plan_code` -> `url` contract.
// The portal validates the bearer session and sources user/price from the server.
const portal = Deno.env.get('PAYMENT_PORTAL_URL')?.replace(/\/$/, '');
const allowedOrigins = (Deno.env.get('PAYMENT_ALLOWED_ORIGINS') || '').split(',').filter(Boolean);

Deno.serve(async (request: Request) => {
  const origin = request.headers.get('origin');
  const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Vary': 'Origin' };
  if (origin && allowedOrigins.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  headers['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type, x-client-info';
  headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
  const reply = (status: number, payload: unknown) => new Response(JSON.stringify(payload), { status, headers });
  if (origin && !allowedOrigins.includes(origin)) return reply(403, { error: 'Origin not allowed' });
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, { error: 'POST required' });
  if (!portal || !portal.startsWith('https://')) return reply(503, { error: 'Payment portal is not configured' });
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'Sign in required' });
  try {
    const text = await request.text();
    if (text.length > 8192) return reply(413, { error: 'Request too large' });
    const input = JSON.parse(text);
    if (typeof input?.plan_code !== 'string') return reply(400, { error: 'plan_code required' });
    const response = await fetch(`${portal}/api/checkout`, {
      method: 'POST', headers: { authorization, 'Content-Type': 'application/json' },
      body: JSON.stringify({ plan_code: input.plan_code, idempotency_key: input.idempotency_key }),
      signal: AbortSignal.timeout(20000), redirect: 'error',
    });
    return reply(response.status, await response.json());
  } catch { return reply(503, { error: 'Checkout unavailable. Please try again.' }); }
});
