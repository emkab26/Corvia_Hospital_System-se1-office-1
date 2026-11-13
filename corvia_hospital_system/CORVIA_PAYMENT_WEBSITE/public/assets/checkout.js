const key = document.querySelector('#idempotency-key');
if (key) key.value = crypto.randomUUID();
for (const link of document.querySelectorAll('[data-plan]')) {
  link.addEventListener('click', () => { document.querySelector('#plan').value = link.dataset.plan; });
}
