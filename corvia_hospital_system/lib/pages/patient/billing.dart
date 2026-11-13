import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/corvia_payment_monitor.dart';
import '../../widgets/payment_website_card.dart';
import '../../widgets/status_view.dart';

final _log = Logger('Billing');

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  String _subscriptionStatus = 'Loading...';
  Future<List<_PricingPlan>>? _plansFuture;
  Future<List<_Invoice>>? _invoicesFuture;
  bool _purchasing = false;
  int _paymentRefreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
    _plansFuture = _PricingPlan.loadActive();
    _invoicesFuture = _Invoice.loadForUser();
  }

  Future<void> _loadSubscription() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      setState(() => _subscriptionStatus = 'Not logged in');
      return;
    }
    try {
      Map<String, dynamic>? access;
      try {
        final raw = await SupabaseService.client.rpc('corvia_account_access');
        if (raw is List && raw.isNotEmpty && raw.first is Map) {
          access = Map<String, dynamic>.from(raw.first as Map);
        } else if (raw is Map) {
          access = Map<String, dynamic>.from(raw);
        }
      } catch (_) {
        // Compatibility fallback while the access rollout migration is pending.
      }

      String status;
      if (access != null) {
        final full = access['has_full_access'] == true;
        final source = access['access_source']?.toString();
        status = full
            ? source == 'existing_account'
                ? 'Full access (existing account)'
                : 'Full access (confirmed payment)'
            : 'Free access';
      } else {
        final legacy = await SupabaseService.client
            .from('subscriptions')
            .select('status')
            .eq('user_id', user.id)
            .maybeSingle();
        status = legacy == null
            ? 'No payment'
            : (legacy['status'] ?? 'Unknown').toString();
      }
      if (!mounted) return;
      setState(() => _subscriptionStatus = status);
    } catch (e) {
      _log.warning('Subscription load failed: $e');
      if (mounted) setState(() => _subscriptionStatus = _friendlyError(e));
    }
  }

  Future<void> _refreshBilling() async {
    final plansFuture = _PricingPlan.loadActive();
    final invoicesFuture = _Invoice.loadForUser();
    setState(() {
      _plansFuture = plansFuture;
      _invoicesFuture = invoicesFuture;
      _paymentRefreshVersion++;
    });
    await _loadSubscription();
  }

  Future<void> _subscribe(_PricingPlan plan) async {
    final user = SupabaseService.currentUser;
    if (user == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      final response = await SupabaseService.client.functions.invoke(
        'create-payment',
        body: {
          'plan_code': plan.code,
        },
      );
      final url = response.data is Map ? response.data['url'] : null;
      if (url == null) {
        _snack('No payment URL returned. Please try again later.');
        return;
      }
      final parsed = Uri.tryParse(url.toString());
      if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
        _snack('Payment URL was invalid.');
        return;
      }
      final launched =
          await launchUrl(parsed, mode: LaunchMode.externalApplication);
      if (!launched) _snack('Could not launch the payment page.');
    } catch (e) {
      _log.warning('Payment error: $e');
      _snack(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Widget _buildInvoicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invoices',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: CorviaColors.accentLight,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<_Invoice>>(
          future: _invoicesFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return StatusView.loading(message: 'Loading invoices...');
            }
            if (snap.hasError) {
              return StatusView.error(
                friendlyMessage: "We couldn't load your invoices.",
                error: snap.error,
                stackTrace: snap.stackTrace,
                onRetry: _refreshBilling,
              );
            }
            final invoices = snap.data ?? const [];
            if (invoices.isEmpty) {
              return StatusView.empty(
                icon: Icons.receipt_long_outlined,
                title: 'No invoices yet',
                subtitle: 'Your billing history will appear here.',
              );
            }
            return Column(
              children: [
                for (final inv in invoices) ...[
                  _InvoiceCard(invoice: inv),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: context.cBgGradient,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            children: [
              Text(
                'Healthcare Access',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: CorviaColors.accentLight,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.cDivider),
                ),
                child: Text(
                  'Subscription Status: $_subscriptionStatus',
                  style: TextStyle(
                      color: CorviaColors.textSecondary, fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              const PaymentWebsiteCard(),
              const SizedBox(height: 16),
              CorviaPaymentMonitor(
                refreshVersion: _paymentRefreshVersion,
              ),
              const SizedBox(height: 24),
              FutureBuilder<List<_PricingPlan>>(
                future: _plansFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child:
                          CircularProgressIndicator(color: CorviaColors.accent),
                    );
                  }
                  if (snap.hasError) {
                    return _MessageBox(
                      icon: Icons.error_outline,
                      message: 'Could not load plans: ${snap.error}',
                    );
                  }
                  final plans = snap.data ?? const [];
                  if (plans.isEmpty) {
                    return const _MessageBox(
                      icon: Icons.info_outline,
                      message: 'No active plans configured. Contact support.',
                    );
                  }
                  return Column(
                    children: [
                      for (final plan in plans) ...[
                        _PlanCard(
                          plan: plan,
                          purchasing: _purchasing,
                          onPurchase: () => _subscribe(plan),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildInvoicesSection(),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _snack('Support: support@corvia.health'),
                child: const Text('Need help? Contact support'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.purchasing,
    required this.onPurchase,
  });

  final _PricingPlan plan;
  final bool purchasing;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    final cardGradient = isDark
        ? LinearGradient(
            colors: [
              CorviaColors.accentDark.withValues(alpha: 1),
              CorviaColors.accent.withValues(alpha: 0.6),
              CorviaColors.accentDark.withValues(alpha: 1),
            ],
          )
        : LinearGradient(
            colors: [
              context.cBgSecondary,
              context.cBgSecondary,
            ],
          );

    final cardTextColor = context.cTextPrimary;
    final cardsubTextColor = context.cTextSecondary;
    final accentColor = context.cAccentReadable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: cardGradient,
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              plan.name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cardTextColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              plan.priceLabel,
              style: TextStyle(
                fontSize: 22,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                plan.description,
                style: TextStyle(color: cardsubTextColor),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (plan.features.isNotEmpty) ...[
            Text(
              'Includes:',
              style: TextStyle(
                color: cardTextColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final f in plan.features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: accentColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(f,
                          style:
                              TextStyle(color: cardsubTextColor, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
          Center(
            child: ElevatedButton(
              onPressed: purchasing ? null : onPurchase,
              child: purchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Pay ${plan.priceLabel}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, color: CorviaColors.accentLight, size: 40),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: CorviaColors.textSecondary)),
        ],
      ),
    );
  }
}

enum _InvoiceStatus {
  paid,
  pending,
  overdue;

  static _InvoiceStatus fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'paid':
      case 'active':
      case 'complete':
      case 'completed':
        return _InvoiceStatus.paid;
      case 'overdue':
      case 'past_due':
      case 'failed':
      case 'expired':
        return _InvoiceStatus.overdue;
      default:
        return _InvoiceStatus.pending;
    }
  }

  String get label => switch (this) {
        _InvoiceStatus.paid => 'Paid',
        _InvoiceStatus.pending => 'Pending',
        _InvoiceStatus.overdue => 'Overdue',
      };

  Color get color => switch (this) {
        _InvoiceStatus.paid => const Color(0xFF2E7D32),
        _InvoiceStatus.pending => const Color(0xFFF9A825),
        _InvoiceStatus.overdue => const Color(0xFFC62828),
      };

  Color get background => switch (this) {
        _InvoiceStatus.paid => const Color(0xFF2E7D32),
        _InvoiceStatus.pending => const Color(0xFFF9A825),
        _InvoiceStatus.overdue => const Color(0xFFC62828),
      };
}

class _Invoice {
  _Invoice({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String description;
  final int amountCents;
  final String currency;
  final _InvoiceStatus status;
  final DateTime? dueDate;

  String get amountLabel {
    final amount = amountCents / 100.0;
    final formatted = NumberFormat('#,##0.00', 'en_ZA').format(amount);
    final symbol = currency == 'ZAR' ? 'R' : '$currency ';
    return '$symbol$formatted';
  }

  String get dueDateLabel {
    if (dueDate == null) return '-';
    return DateFormat('dd MMM yyyy').format(dueDate!);
  }

  static Future<List<_Invoice>> loadForUser() async {
    final user = SupabaseService.currentUser;
    if (user == null) return const [];
    // Patient billing records are the rows in `subscriptions`; there is no
    // separate invoices table in the Corvia schema.
    final res = await SupabaseService.client
        .from('subscriptions')
        .select(
          'id, plan, plan_name, amount, currency, status, '
          'starts_at, ends_at, created_at',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(20);

    return (res as List).map((row) {
      DateTime? parse(Object? value) =>
          value == null ? null : DateTime.tryParse(value.toString());

      final planName = row['plan_name']?.toString().trim() ?? '';
      final plan = row['plan']?.toString().trim() ?? '';
      final amount = (row['amount'] as num?) ??
          num.tryParse(row['amount']?.toString() ?? '') ??
          0;

      return _Invoice(
        id: row['id']?.toString() ?? '',
        description: planName.isNotEmpty
            ? planName
            : plan.isNotEmpty
                ? plan
                : 'Corvia subscription',
        amountCents: (amount * 100).round(),
        currency: row['currency']?.toString() ?? 'ZAR',
        status: _InvoiceStatus.fromString(row['status']?.toString()),
        dueDate: parse(row['starts_at']) ?? parse(row['created_at']),
      );
    }).toList();
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.status);

  final _InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.background.withValues(alpha: 0.18),
        border: Border.all(color: status.color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final _Invoice invoice;

  Future<void> _downloadInvoicePdf(BuildContext context) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Invoice',
                    style: pw.TextStyle(
                      fontSize: 28,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.SizedBox(height: 16),
                pw.Text(invoice.description,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Due date:',
                            style: pw.TextStyle(
                                fontSize: 12, color: PdfColors.grey700)),
                        pw.Text(invoice.dueDateLabel,
                            style: pw.TextStyle(fontSize: 14)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Amount:',
                            style: pw.TextStyle(
                                fontSize: 12, color: PdfColors.grey700)),
                        pw.Text(invoice.amountLabel,
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            )),
                      ],
                    ),
                  ],
                ),
                pw.Divider(height: 32, thickness: 1, color: PdfColors.grey300),
                pw.Text('Status',
                    style:
                        pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                pw.Text(invoice.status.label,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: invoice.status == _InvoiceStatus.overdue
                          ? PdfColors.red
                          : PdfColors.green,
                    )),
                pw.Spacer(),
                pw.Text('Generated by Corvia Health',
                    style:
                        pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'invoice_${invoice.id}.pdf',
      );
    } catch (e, st) {
      _log.warning('Invoice PDF generation failed', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate invoice PDF.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.description,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Date: ${invoice.dueDateLabel}',
                  style: TextStyle(
                    color: CorviaColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                invoice.amountLabel,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              _StatusTag(invoice.status),
              const SizedBox(height: 8),
              IconButton(
                onPressed: () => _downloadInvoicePdf(context),
                icon: const Icon(Icons.picture_as_pdf),
                color: CorviaColors.accentLight,
                tooltip: 'Download invoice PDF',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricingPlan {
  _PricingPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.priceCents,
    required this.currency,
    required this.billingPeriod,
    required this.features,
  });

  final String code;
  final String name;
  final String description;
  final int priceCents;
  final String currency;
  final String billingPeriod;
  final List<String> features;

  String get priceLabel {
    final amount = priceCents / 100.0;
    final formatted = NumberFormat('#,##0.00', 'en_ZA').format(amount);
    final symbol = currency == 'ZAR' ? 'R' : '$currency ';
    final suffix = switch (billingPeriod) {
      'monthly' => '/mo',
      'yearly' => '/yr',
      _ => ' once-off',
    };
    return '$symbol$formatted$suffix';
  }

  static Future<List<_PricingPlan>> loadActive() async {
    final res = await SupabaseService.client
        .from('pricing_plans')
        .select(
            'code, name, description, price_cents, currency, billing_period, features')
        .eq('is_active', true)
        .order('display_order');

    return (res as List).map((row) {
      final features = (row['features'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[];
      return _PricingPlan(
        code: row['code']?.toString() ?? '',
        name: row['name']?.toString() ?? 'Plan',
        description: row['description']?.toString() ?? '',
        priceCents: (row['price_cents'] as num?)?.toInt() ?? 0,
        currency: row['currency']?.toString() ?? 'ZAR',
        billingPeriod: row['billing_period']?.toString() ?? 'one_off',
        features: features,
      );
    }).toList();
  }
}
