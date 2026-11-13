const portal = Deno.env.get('PAYMENT_PORTAL_URL')?.replace(/\/$/, '');
const allowedOrigins = (Deno.env.get('PAYMENT_ALLOWED_ORIGINS') || '').split(',').filter(Boolean);
Deno.serve(async (request: Request) => {
  const origin = request.headers.get('origin');
  const headers: Record<string, string> = {
    'Content-Type': 'application/json', 'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  if (origin && allowedOrigins.includes(origin)) headers['Access-Control-Allow-Origin'] = origin;
  const reply = (status: number, payload: unknown) => new Response(JSON.stringify(payload), { status, headers });
  if (origin && !allowedOrigins.includes(origin)) return reply(403, { error: 'Origin not allowed' });
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, { error: 'POST required' });
  if (!portal?.startsWith('https://')) return reply(503, { error: 'Payment portal is not configured' });
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'Sign in required' });
  try {
    const text = await request.text();
    if (text.length > 8192) return reply(413, { error: 'Request too large' });
    const input = JSON.parse(text);
    if (!/^[0-9a-f-]{36}$/i.test(input?.payment_id || '') || !['reconcile', 'link'].includes(input?.action)) return reply(400, { error: 'Invalid review request' });
    const route = input.action === 'link' ? 'payment-link' : 'reconcile';
    const response = await fetch(`${portal}/api/${route}/${input.payment_id}`, {
      method: 'POST', headers: { authorization }, signal: AbortSignal.timeout(60000), redirect: 'error',
    });
    return reply(response.status, await response.json());
  } catch { return reply(503, { error: 'Payment review unavailable. Please try again.' }); }
});
