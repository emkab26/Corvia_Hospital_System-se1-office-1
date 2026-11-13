export class Database {
  constructor(config, fetcher = fetch) { this.config = config; this.fetcher = fetcher; }
  async request(path, { token, method = 'GET', body, service = false } = {}) {
    const key = service ? this.config.serviceKey : this.config.anonKey;
    const response = await this.fetcher(`${this.config.supabaseUrl}${path}`, {
      method, headers: { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000), redirect: 'error',
    });
    if (!response.ok) {
      // Do not expose upstream SQL/auth responses, tokens or customer data to clients/logs.
      const error = new Error('Database request failed'); error.status = response.status; throw error;
    }
    return response.status === 204 ? null : response.json();
  }
  rpc(name, body, token) { return this.request(`/rest/v1/rpc/${name}`, { method: 'POST', body, token, service: !token }); }
  user(token) { return this.request('/auth/v1/user', { token }); }
  login(email, password) { return this.request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password } }); }
  plans() { return this.request('/rest/v1/pricing_plans?select=code,name,description,price_cents,currency,billing_period&is_active=eq.true&currency=eq.ZAR&order=display_order', { service: true }); }
  async payment(id) {
    const rows = await this.request(`/rest/v1/corvia_payment_attempts?id=eq.${encodeURIComponent(id)}&select=*`, { service: true });
    return rows[0];
  }
  create(user, plan, key, environment) { return this.rpc('corvia_create_payment', { p_user_id: user.id, p_email: user.email, p_plan_code: plan, p_idempotency_key: key, p_environment: environment }); }
}
