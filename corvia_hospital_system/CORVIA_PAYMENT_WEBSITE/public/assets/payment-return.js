const root = document.querySelector('#payment-result');
const query = location.search;
const receipt = document.querySelector('#receipt');
receipt.href = `/receipt/${root.dataset.id}${query}`;
let attempts = 0;
let timer;
let busy = false;
async function refresh() {
  if (busy) return;
  busy = true;
  clearTimeout(timer);
  const message = document.querySelector('#status-message');
  try {
    const response = await fetch(`/api/status/${root.dataset.id}${query}`, { cache: 'no-store' });
    if (!response.ok) throw new Error('Status unavailable');
    const payment = await response.json();
    const labels = { paid: 'Payment confirmed', pending: 'Awaiting confirmation', failed: 'Payment failed', cancelled: 'Payment cancelled' };
    document.querySelector('#status-title').textContent = labels[payment.status] || 'Status unavailable';
    message.textContent = payment.status === 'paid' ? 'PayFast has confirmed this payment.' : payment.status === 'pending' ? 'Still awaiting PayFast confirmation. Check again or return to Billing later.' : 'No access has been activated for this attempt. You can start a new checkout from the plans page.';
    document.querySelector('#status-detail').textContent = payment.review_required ? 'This payment needs review. Contact your billing team with the reference.' : '';
    receipt.hidden = payment.status !== 'paid';
    if (payment.status === 'pending' && ++attempts < 12) timer = setTimeout(refresh, 5000);
  } catch {
    message.textContent = 'We could not check your payment. Use Check again or view Billing in Corvia. No payment status has been changed.';
  } finally { busy = false; }
}
document.querySelector('#refresh-status').addEventListener('click', refresh);
refresh();
