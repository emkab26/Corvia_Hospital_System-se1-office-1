export function loadConfig(env = process.env) {
  const sandbox = (env.PAYFAST_MODE || 'sandbox') === 'sandbox';
  if (!['sandbox', 'live'].includes(env.PAYFAST_MODE || 'sandbox')) throw new Error('Invalid PAYFAST_MODE');
  const baseUrl = new URL(env.PORTAL_BASE_URL || 'http://localhost:8080');
  if (baseUrl.pathname !== '/' || baseUrl.search || baseUrl.hash || baseUrl.username) throw new Error('PORTAL_BASE_URL must be an origin');
  if (baseUrl.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(baseUrl.hostname)) throw new Error('Public portal requires HTTPS');
  if (!sandbox && env.PAYFAST_LIVE_ENABLED !== 'true') throw new Error('Live payments require PAYFAST_LIVE_ENABLED=true');
  if (!sandbox && baseUrl.protocol !== 'https:') throw new Error('Live payments require HTTPS');
  const required = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'PAYFAST_MERCHANT_ID', 'PAYFAST_MERCHANT_KEY', 'PAYFAST_PASSPHRASE', 'PORTAL_LINK_SECRET'];
  const missing = required.filter(key => !env[key]);
  const preview = env.PORTAL_PREVIEW === 'true';
  if (!preview && missing.length) throw new Error(`Missing configuration: ${missing.join(', ')}`);
  if (!preview && env.PORTAL_LINK_SECRET.length < 32) throw new Error('PORTAL_LINK_SECRET must have at least 32 characters');
  if (!preview) {
    const supabase = new URL(env.SUPABASE_URL);
    if (supabase.username || supabase.search || supabase.hash || (supabase.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(supabase.hostname))) throw new Error('Supabase requires a secure server URL');
  }
  if (preview && !sandbox) throw new Error('Preview is sandbox only');
  return {
    port: Number(env.PORT || 8080), host: env.HOST || '127.0.0.1', baseUrl: baseUrl.origin,
    sandbox, preview, environment: sandbox ? 'sandbox' : 'live',
    supabaseUrl: env.SUPABASE_URL?.replace(/\/$/, ''), anonKey: env.SUPABASE_ANON_KEY,
    serviceKey: env.SUPABASE_SERVICE_ROLE_KEY, merchantId: env.PAYFAST_MERCHANT_ID,
    merchantKey: env.PAYFAST_MERCHANT_KEY, passphrase: env.PAYFAST_PASSPHRASE,
    linkSecret: env.PORTAL_LINK_SECRET,
    // Configure only when a trusted reverse proxy OVERWRITES this header and the origin is private.
    proxyHeader: (env.TRUSTED_CLIENT_IP_HEADER || '').toLowerCase(),
    payfastHost: sandbox ? 'sandbox.payfast.co.za' : 'www.payfast.co.za',
  };
}
