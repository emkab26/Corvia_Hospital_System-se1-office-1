import 'package:supabase_flutter/supabase_flutter.dart';

class CorviaEntitlements {
  const CorviaEntitlements({
    required this.hospitalId,
    required this.plan,
    required this.subscriptionStatus,
    required this.fullAccess,
    required this.features,
    this.currentPeriodEnd,
    this.gracePeriodEnd,
    this.lastPaymentAt,
  });

  final String hospitalId;
  final String plan;
  final String subscriptionStatus;
  final bool fullAccess;
  final Map<String, bool> features;
  final DateTime? currentPeriodEnd;
  final DateTime? gracePeriodEnd;
  final DateTime? lastPaymentAt;

  bool hasFeature(String feature) => features[feature] ?? false;

  factory CorviaEntitlements.fromJson(Map<String, dynamic> json) {
    final features = <String, bool>{};
    final rawFeatures = json['features'];
    if (rawFeatures is Map) {
      for (final entry in rawFeatures.entries) {
        features[entry.key.toString()] = entry.value == true;
      }
    }
    return CorviaEntitlements(
      hospitalId: json['hospital_id']?.toString() ?? '',
      plan: json['plan']?.toString() ?? 'basic',
      subscriptionStatus:
          json['subscription_status']?.toString() ?? 'basic',
      fullAccess: json['full_access'] == true,
      features: features,
      currentPeriodEnd: _date(json['current_period_end']),
      gracePeriodEnd: _date(json['grace_period_end']),
      lastPaymentAt: _date(json['last_payment_at']),
    );
  }

  static DateTime? _date(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString())?.toLocal();
}

class CorviaPaymentRecord {
  const CorviaPaymentRecord({
    required this.reference,
    required this.status,
    required this.verificationStatus,
    required this.amountDue,
    required this.currency,
    required this.createdAt,
    this.amountReceived,
    this.providerPaymentId,
    this.paidAt,
    this.lastCheckedAt,
    this.verificationError,
    this.receiptNumber,
    this.planCode,
    this.planName,
    this.environment,
    this.reviewRequired = false,
    this.duplicateCount = 0,
    this.reviewState,
    this.reviewReason,
  });

  final String reference;
  final String status;
  final String verificationStatus;
  final double amountDue;
  final double? amountReceived;
  final String currency;
  final String? providerPaymentId;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? lastCheckedAt;
  final String? verificationError;
  final String? receiptNumber;
  final String? planCode;
  final String? planName;
  final String? environment;
  final bool reviewRequired;
  final int duplicateCount;
  final String? reviewState;
  final String? reviewReason;

  bool get isPaid =>
      status == 'paid' && verificationStatus == 'verified';

  bool get isPending => status == 'pending' || status == 'processing';

  bool get needsAttention =>
      reviewRequired ||
      status == 'review_required' ||
      status == 'failed' ||
      verificationStatus == 'amount_mismatch' ||
      verificationStatus == 'signature_mismatch' ||
      verificationStatus == 'merchant_mismatch' ||
      verificationStatus == 'source_ip_mismatch' ||
      verificationStatus == 'server_confirmation_failed';

  factory CorviaPaymentRecord.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString().toLowerCase() ?? 'pending';
    final reviewRequired = json['review_required'] == true;
    final reasonCode = json['reason_code']?.toString();
    final amountCents = json['amount_cents'];
    final rawAmount = json['amount_due'];

    String verification = json['verification_status']?.toString() ?? '';
    if (verification.isEmpty) {
      if (status == 'paid') {
        verification = 'verified';
      } else if (reviewRequired) {
        verification = reasonCode ?? 'review_required';
      } else if (json['last_checked_at'] != null) {
        verification = 'checked';
      } else {
        verification = 'awaiting_notification';
      }
    }

    return CorviaPaymentRecord(
      reference: json['id']?.toString() ??
          json['reference']?.toString() ??
          '',
      status: status,
      verificationStatus: verification,
      amountDue: amountCents is num
          ? amountCents.toDouble() / 100
          : (rawAmount as num?)?.toDouble() ?? 0,
      amountReceived: (json['amount_received'] as num?)?.toDouble(),
      currency: json['currency']?.toString() ?? 'ZAR',
      providerPaymentId: json['provider_payment_id']?.toString(),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      paidAt: _date(json['paid_at']),
      lastCheckedAt: _date(json['last_checked_at']),
      verificationError:
          json['verification_error']?.toString() ?? reasonCode,
      receiptNumber: json['receipt_number']?.toString(),
      planCode: json['plan_code']?.toString(),
      planName: json['plan_name']?.toString(),
      environment: json['environment']?.toString(),
      reviewRequired: reviewRequired,
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
      reviewState: json['review_state']?.toString(),
      reviewReason: json['review_reason']?.toString(),
    );
  }

  static DateTime? _date(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString())?.toLocal();
}

class CorviaBillingSnapshot {
  const CorviaBillingSnapshot({
    required this.entitlements,
    required this.payments,
  });

  final CorviaEntitlements entitlements;
  final List<CorviaPaymentRecord> payments;

  CorviaPaymentRecord? get latestPayment =>
      payments.isEmpty ? null : payments.first;

  factory CorviaBillingSnapshot.fromJson(Map<String, dynamic> json) {
    final entitlementRaw = json['entitlements'];
    if (entitlementRaw is! Map) {
      throw Exception('Corvia billing response did not contain entitlements.');
    }
    final payments = <CorviaPaymentRecord>[];
    final rawPayments = json['payments'];
    if (rawPayments is List) {
      for (final row in rawPayments.whereType<Map>()) {
        payments.add(
          CorviaPaymentRecord.fromJson(Map<String, dynamic>.from(row)),
        );
      }
    }
    return CorviaBillingSnapshot(
      entitlements: CorviaEntitlements.fromJson(
        Map<String, dynamic>.from(entitlementRaw),
      ),
      payments: payments,
    );
  }
}

class CorviaSubscriptionService {
  CorviaSubscriptionService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<CorviaBillingSnapshot> loadBillingSnapshot({
    String? hospitalId,
    bool staff = false,
  }) async {
    if (_supabase.auth.currentUser == null) {
      throw Exception('You are not signed in.');
    }
    if (staff && (hospitalId == null || hospitalId.trim().isEmpty)) {
      throw Exception('The hospital link is missing.');
    }

    dynamic query = _supabase.from('corvia_payment_attempts').select(
          'id,user_id,hospital_id,plan_code,plan_name,billing_period,'
          'amount_cents,currency,environment,status,provider_payment_id,'
          'reason_code,review_required,duplicate_count,created_at,'
          'updated_at,last_checked_at,paid_at',
        );
    if (staff) query = query.eq('hospital_id', hospitalId!);
    final rawAttempts =
        await query.order('created_at', ascending: false).limit(50);
    final attempts = _rows(rawAttempts);
    final ids = attempts
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    final receiptsByPayment = <String, String>{};
    final reviewsByPayment = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final receiptRows = _rows(await _supabase
          .from('corvia_payment_receipts')
          .select('payment_id,receipt_number')
          .inFilter('payment_id', ids));
      for (final row in receiptRows) {
        final paymentId = row['payment_id']?.toString();
        final receipt = row['receipt_number']?.toString();
        if (paymentId != null && receipt != null) {
          receiptsByPayment[paymentId] = receipt;
        }
      }

      if (staff) {
        try {
          final reviewRows = _rows(await _supabase
              .from('corvia_payment_reviews')
              .select('payment_id,reason,state,raised_at,resolution,resolved_at')
              .inFilter('payment_id', ids));
          for (final row in reviewRows) {
            final paymentId = row['payment_id']?.toString();
            if (paymentId != null) reviewsByPayment[paymentId] = row;
          }
        } on PostgrestException catch (error) {
          // The base ledger remains usable before the optional review upgrade.
          if (error.code != '42P01' && error.code != 'PGRST205') rethrow;
        }
      }
    }

    final payments = attempts.map((attempt) {
      final id = attempt['id']?.toString() ?? '';
      final review = reviewsByPayment[id];
      final receipt = receiptsByPayment[id];
      return CorviaPaymentRecord.fromJson({
        ...attempt,
        if (receipt != null) 'receipt_number': receipt,
        if (review != null) ...{
          'review_state': review['state'],
          'review_reason': review['reason'],
        },
      });
    }).toList();

    CorviaEntitlements entitlements = CorviaEntitlements(
      hospitalId: hospitalId ?? '',
      plan: 'basic',
      subscriptionStatus: 'basic',
      fullAccess: false,
      features: const {},
    );
    if (!staff) {
      var accountAccessLoaded = false;
      try {
        final accessRows = _rows(
          await _supabase.rpc('corvia_account_access'),
        );
        if (accessRows.isNotEmpty) {
          final access = accessRows.first;
          final fullAccess = access['has_full_access'] == true;
          final paid = payments.where((payment) => payment.isPaid);
        entitlements = CorviaEntitlements(
            hospitalId: hospitalId ?? '',
            plan: access['access_tier']?.toString() ?? 'basic',
            subscriptionStatus:
                access['access_source']?.toString() ?? 'basic',
            fullAccess: fullAccess,
            features: const {},
            currentPeriodEnd:
                CorviaPaymentRecord._date(access['valid_until']),
            lastPaymentAt: paid.isEmpty ? null : paid.first.paidAt,
          );
          accountAccessLoaded = true;
        }
      } on PostgrestException catch (error) {
        if (error.code != '42883' && error.code != 'PGRST202') rethrow;
      }

      if (!accountAccessLoaded) {
        final entitlementRows = _rows(await _supabase
            .from('corvia_payment_entitlements')
            .select('plan_code,valid_from,valid_until')
            .order('valid_until', ascending: false)
            .limit(20));
        final now = DateTime.now();
        final active = entitlementRows.where((row) {
          final from = CorviaPaymentRecord._date(row['valid_from']);
          final until = CorviaPaymentRecord._date(row['valid_until']);
          return from != null &&
              until != null &&
              !from.isAfter(now) &&
              until.isAfter(now);
        }).toList();
        if (active.isNotEmpty) {
          final first = active.first;
          final paid = payments.where((payment) => payment.isPaid);
          entitlements = CorviaEntitlements(
            hospitalId: hospitalId ?? '',
            plan: first['plan_code']?.toString() ?? 'paid',
            subscriptionStatus: 'active',
            fullAccess: true,
            features: const {},
            currentPeriodEnd:
                CorviaPaymentRecord._date(first['valid_until']),
            lastPaymentAt: paid.isEmpty ? null : paid.first.paidAt,
          );
        }
      }
    }

    return CorviaBillingSnapshot(
      entitlements: entitlements,
      payments: payments,
    );
  }

  Future<String> requestPaymentLink(String paymentId) async {
    final response = await _supabase.functions.invoke(
      'payment-review',
      body: {'payment_id': paymentId, 'action': 'link'},
    );
    final data = response.data;
    if (data is! Map || data['url'] == null) {
      throw Exception('The payment status link is not available.');
    }
    return data['url'].toString();
  }

  Future<String> reconcilePayment(String paymentId) async {
    final response = await _supabase.functions.invoke(
      'payment-review',
      body: {'payment_id': paymentId, 'action': 'reconcile'},
    );
    final data = response.data;
    if (data is! Map || data['message'] == null) {
      throw Exception('The PayFast verification response was invalid.');
    }
    return data['message'].toString();
  }

  Future<void> saveReview({
    required String paymentId,
    required String reason,
    required bool resolve,
  }) async {
    await _supabase.rpc('corvia_payment_escalate', params: {
      'p_payment_id': paymentId,
      'p_reason': reason,
      'p_resolve': resolve,
    });
  }

  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : const [];
}
