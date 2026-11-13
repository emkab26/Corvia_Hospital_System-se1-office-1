import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/corvia_subscription_service.dart';

class CorviaPaymentMonitor extends StatefulWidget {
  const CorviaPaymentMonitor({
    super.key,
    this.hospitalId,
    this.staff = false,
    this.refreshVersion = 0,
  });

  final String? hospitalId;
  final bool staff;
  final int refreshVersion;

  @override
  State<CorviaPaymentMonitor> createState() =>
      _CorviaPaymentMonitorState();
}

class _CorviaPaymentMonitorState extends State<CorviaPaymentMonitor> {
  final CorviaSubscriptionService _service = CorviaSubscriptionService();

  bool _loading = true;
  String? _busyReference;
  String? _error;
  CorviaBillingSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CorviaPaymentMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hospitalId != widget.hospitalId ||
        oldWidget.staff != widget.staff ||
        oldWidget.refreshVersion != widget.refreshVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await _service.loadBillingSnapshot(
        hospitalId: widget.hospitalId,
        staff: widget.staff,
      );
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '42P01' || error.code == 'PGRST205') {
        return 'Payment monitoring is not installed in Supabase yet. Run the payment SQL package first.';
      }
      if (error.code == '42501' || error.code == 'PGRST301') {
        return 'This account does not have access to the payment ledger.';
      }
      return 'The payment ledger could not be loaded from Supabase.';
    }
    final text = error.toString().toLowerCase();
    if (text.contains('not signed in')) return 'Sign in again to view payments.';
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('failed to fetch')) {
      return 'The payment service could not be reached. Check the connection and try again.';
    }
    return 'Payment monitoring is temporarily unavailable.';
  }

  Future<void> _openPayment(CorviaPaymentRecord payment) async {
    if (_busyReference != null) return;
    setState(() => _busyReference = payment.reference);
    try {
      final value = await _service.requestPaymentLink(payment.reference);
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.host.isEmpty ||
          !const ['https', 'http'].contains(uri.scheme)) {
        throw Exception('Invalid payment link.');
      }
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('Could not open the payment page.');
    } catch (error) {
      _message(_friendlyActionError(error), error: true);
    } finally {
      if (mounted) setState(() => _busyReference = null);
    }
  }

  Future<void> _reconcile(CorviaPaymentRecord payment) async {
    if (_busyReference != null || !widget.staff) return;
    setState(() => _busyReference = payment.reference);
    try {
      final message = await _service.reconcilePayment(payment.reference);
      _message(message);
      await _load();
    } catch (error) {
      _message(_friendlyActionError(error), error: true);
    } finally {
      if (mounted) setState(() => _busyReference = null);
    }
  }

  Future<void> _review(
    CorviaPaymentRecord payment, {
    required bool resolve,
  }) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(resolve ? 'Resolve billing review' : 'Record billing review'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: resolve ? 'Resolution' : 'Review reason',
            hintText: resolve
                ? 'Describe how the review was resolved.'
                : 'Describe the follow-up required. This does not mark the payment paid.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 5) Navigator.of(dialogContext).pop(value);
            },
            child: Text(resolve ? 'Resolve review' : 'Save review'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 5 || _busyReference != null) return;
    setState(() => _busyReference = payment.reference);
    try {
      await _service.saveReview(
        paymentId: payment.reference,
        reason: reason,
        resolve: resolve,
      );
      _message(resolve ? 'Billing review resolved.' : 'Billing review recorded.');
      await _load();
    } catch (error) {
      _message(_friendlyActionError(error), error: true);
    } finally {
      if (mounted) setState(() => _busyReference = null);
    }
  }

  String _friendlyActionError(Object error) {
    if (error is FunctionException) {
      if (error.status == 503) {
        return 'The hosted payment portal is not configured yet.';
      }
      if (error.status == 401 || error.status == 403) {
        return 'Your account is not allowed to perform this payment action.';
      }
      return 'The payment action could not be completed.';
    }
    if (error is PostgrestException) {
      if (error.code == '42883' || error.code == 'PGRST202') {
        return 'Install the payment review SQL upgrade before using this action.';
      }
      return 'Supabase rejected the payment review action.';
    }
    return 'The payment action could not be completed. Please try again.';
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment monitoring',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      );
    }

    final payments = _snapshot?.payments ?? const <CorviaPaymentRecord>[];
    final paid = payments.where((payment) => payment.isPaid).length;
    final pending = payments.where((payment) => payment.isPending).length;
    final attention = payments.where((payment) => payment.needsAttention).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.monitor_heart_outlined,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Corvia Payment Monitor',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    widget.staff
                        ? 'Server-confirmed PayFast activity for this hospital.'
                        : 'Your server-confirmed PayFast activity.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh payment monitor',
              onPressed: _busyReference == null ? _load : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryChip('$paid verified', Icons.verified_rounded, Colors.green),
            _SummaryChip('$pending pending', Icons.schedule_rounded, Colors.orange),
            _SummaryChip(
              '$attention attention',
              Icons.warning_amber_rounded,
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (payments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 38),
                SizedBox(height: 8),
                Text(
                  'No Corvia payments yet',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'Payment attempts will appear here after checkout starts.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...payments.take(20).map((payment) => _paymentCard(context, payment)),
      ],
    );
  }

  Widget _paymentCard(BuildContext context, CorviaPaymentRecord payment) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = payment.isPaid
        ? Colors.green
        : payment.needsAttention
            ? Colors.red
            : payment.isPending
                ? Colors.orange
                : scheme.primary;
    final busy = _busyReference == payment.reference;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                payment.isPaid
                    ? Icons.verified_rounded
                    : payment.needsAttention
                        ? Icons.warning_amber_rounded
                        : Icons.schedule_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.planName ?? payment.planCode ?? 'Corvia payment',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SelectableText(
                      payment.reference,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                _money(payment.amountDue, payment.currency),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow('Status', _status(payment.status)),
          _InfoRow('Verification', payment.verificationStatus),
          _InfoRow('Created', _date(payment.createdAt)),
          if (payment.environment != null)
            _InfoRow('Environment', payment.environment!),
          if (payment.providerPaymentId != null)
            _InfoRow('PayFast ID', payment.providerPaymentId!),
          if (payment.receiptNumber != null)
            _InfoRow('Receipt', payment.receiptNumber!),
          if (payment.duplicateCount > 0)
            _InfoRow('Duplicate notifications', '${payment.duplicateCount}'),
          if (payment.reviewReason != null)
            _InfoRow('Review', payment.reviewReason!),
          if (payment.verificationError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Attention: ${payment.verificationError}',
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          if (busy)
            const LinearProgressIndicator()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openPayment(payment),
                  icon: Icon(payment.isPaid
                      ? Icons.receipt_long_rounded
                      : Icons.open_in_new_rounded),
                  label: Text(payment.isPaid ? 'Open receipt' : 'Open status'),
                ),
                if (widget.staff)
                  OutlinedButton.icon(
                    onPressed: () => _reconcile(payment),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Verify with PayFast'),
                  ),
                if (widget.staff && payment.reviewState != 'open')
                  TextButton.icon(
                    onPressed: () => _review(payment, resolve: false),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Record review'),
                  ),
                if (widget.staff && payment.reviewState == 'open')
                  TextButton.icon(
                    onPressed: () => _review(payment, resolve: true),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Resolve review'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _money(num value, String currency) =>
      currency.toUpperCase() == 'ZAR'
          ? 'R${value.toStringAsFixed(2)}'
          : '${currency.toUpperCase()} ${value.toStringAsFixed(2)}';

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _status(String status) => switch (status.toLowerCase()) {
        'paid' => 'Paid',
        'pending' => 'Pending',
        'failed' => 'Failed',
        'cancelled' => 'Cancelled',
        _ => status,
      };
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
