import 'package:flutter/material.dart';

import '../services/corvia_subscription_service.dart';

class CorviaSubscriptionCard extends StatelessWidget {
  const CorviaSubscriptionCard({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.busy,
    required this.onRefresh,
    required this.onUpgrade,
    required this.onCheckPayment,
    required this.onOpenReceipt,
    this.errorMessage,
  });

  final CorviaBillingSnapshot? snapshot;

  final bool loading;
  final bool busy;

  final VoidCallback onRefresh;
  final VoidCallback onUpgrade;

  final ValueChanged<CorviaPaymentRecord>
      onCheckPayment;

  final ValueChanged<CorviaPaymentRecord>
      onOpenReceipt;

  final String? errorMessage;

  String _money(
    num value,
    String currency,
  ) {
    if (currency.toUpperCase() == 'ZAR') {
      return 'R${value.toStringAsFixed(2)}';
    }

    return '${currency.toUpperCase()} '
        '${value.toStringAsFixed(2)}';
  }

  String _date(DateTime? value) {
    if (value == null) {
      return '—';
    }

    final d =
        value.day.toString().padLeft(2, '0');

    final m =
        value.month.toString().padLeft(2, '0');

    return '$d/$m/${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final entitlements =
        snapshot?.entitlements;

    final latest =
        snapshot?.latestPayment;

    final fullAccess =
        entitlements?.fullAccess == true;

    final planName = fullAccess
        ? 'Corvia Full'
        : 'Corvia Basic';

    final status =
        entitlements?.subscriptionStatus ??
            'basic';

    final statusColor = fullAccess
        ? Colors.green
        : status == 'grace'
            ? Colors.orange
            : colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              statusColor.withValues(
            alpha: 0.30,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.06,
            ),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 150,
              child: Center(
                child:
                    CircularProgressIndicator(),
              ),
            )
          : Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: statusColor
                            .withValues(
                          alpha: 0.12,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: Icon(
                        fullAccess
                            ? Icons
                                .verified_rounded
                            : Icons
                                .workspace_premium_outlined,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            'Corvia Subscription',
                            style: theme
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          const SizedBox(
                            height: 2,
                          ),
                          Text(
                            planName,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight:
                                  FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed:
                          busy ? null : onRefresh,
                      icon: const Icon(
                        Icons.refresh_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon:
                          Icons.circle_rounded,
                      label:
                          status.toUpperCase(),
                      color: statusColor,
                    ),
                    if (entitlements
                            ?.currentPeriodEnd !=
                        null)
                      _InfoPill(
                        icon:
                            Icons.event_rounded,
                        label:
                            'Valid until '
                            '${_date(entitlements!.currentPeriodEnd)}',
                        color:
                            colorScheme.primary,
                      ),
                    if (entitlements
                            ?.lastPaymentAt !=
                        null)
                      _InfoPill(
                        icon:
                            Icons.payments_rounded,
                        label:
                            'Last paid '
                            '${_date(entitlements!.lastPaymentAt)}',
                        color: Colors.green,
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                Text(
                  fullAccess
                      ? 'Premium Corvia hospital features are active.'
                      : 'Core clinical access remains available. '
                          'Premium Corvia hospital features require an active subscription.',
                  style: theme
                      .textTheme.bodyMedium,
                ),

                if (errorMessage != null &&
                    errorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red
                          .withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                if (latest != null) ...[
                  const SizedBox(height: 20),
                  Divider(
                    color: theme.dividerColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Latest payment',
                    style: theme
                        .textTheme.titleSmall
                        ?.copyWith(
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PaymentRow(
                    label: 'Reference',
                    value: latest.reference,
                  ),
                  _PaymentRow(
                    label: 'Status',
                    value:
                        latest.status,
                  ),
                  _PaymentRow(
                    label: 'Verification',
                    value: latest
                        .verificationStatus,
                  ),
                  _PaymentRow(
                    label: 'Expected',
                    value: _money(
                      latest.amountDue,
                      latest.currency,
                    ),
                  ),
                  if (latest.amountReceived !=
                      null)
                    _PaymentRow(
                      label: 'Received',
                      value: _money(
                        latest
                            .amountReceived!,
                        latest.currency,
                      ),
                    ),
                  if (latest
                          .providerPaymentId !=
                      null)
                    _PaymentRow(
                      label: 'PayFast ID',
                      value: latest
                          .providerPaymentId!,
                    ),
                  if (latest.receiptNumber !=
                      null)
                    _PaymentRow(
                      label: 'Receipt',
                      value:
                          latest.receiptNumber!,
                    ),
                ],

                const SizedBox(height: 20),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (!fullAccess)
                      ElevatedButton.icon(
                        onPressed:
                            busy
                                ? null
                                : onUpgrade,
                        icon: const Icon(
                          Icons
                              .workspace_premium_rounded,
                        ),
                        label: const Text(
                          'Upgrade to Corvia Full',
                        ),
                      ),

                    if (latest != null)
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () =>
                                onCheckPayment(
                                  latest,
                                ),
                        icon: const Icon(
                          Icons
                              .verified_user_outlined,
                        ),
                        label: const Text(
                          'Check Payment',
                        ),
                      ),

                    if (latest?.isPaid == true)
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () =>
                                onOpenReceipt(
                                  latest!,
                                ),
                        icon: const Icon(
                          Icons
                              .receipt_long_rounded,
                        ),
                        label: const Text(
                          'Receipt',
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color:
            color.withValues(alpha: 0.10),
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color:
              color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 3,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}