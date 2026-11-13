import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CorviaPaymentCheckResult {
  const CorviaPaymentCheckResult({
    required this.reference,
    required this.status,
    required this.verificationStatus,
    required this.amountDue,
    required this.currency,
    this.amountReceived,
    this.providerPaymentId,
    this.paidAt,
    this.lastCheckedAt,
    this.receiptUrl,
    this.receiptPdfUrl,
    this.verificationError,
  });

  final String reference;
  final String status;
  final String verificationStatus;

  final double amountDue;
  final double? amountReceived;
  final String currency;

  final String? providerPaymentId;

  final DateTime? paidAt;
  final DateTime? lastCheckedAt;

  final String? receiptUrl;
  final String? receiptPdfUrl;

  final String? verificationError;

  bool get isPaid {
    return status == 'paid' &&
        verificationStatus == 'verified';
  }

  bool get needsAttention {
    return status == 'review_required' ||
        status == 'failed';
  }

  factory CorviaPaymentCheckResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return CorviaPaymentCheckResult(
      reference:
          json['reference']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'pending',
      verificationStatus:
          json['verification_status']?.toString() ??
              'not_checked',
      amountDue:
          (json['amount_due'] as num?)
                  ?.toDouble() ??
              0,
      amountReceived:
          (json['amount_received'] as num?)
              ?.toDouble(),
      currency:
          json['currency']?.toString() ?? 'ZAR',
      providerPaymentId:
          json['provider_payment_id']?.toString(),
      paidAt:
          DateTime.tryParse(
            json['paid_at']?.toString() ?? '',
          )?.toLocal(),
      lastCheckedAt:
          DateTime.tryParse(
            json['last_checked_at']?.toString() ??
                '',
          )?.toLocal(),
      receiptUrl:
          json['receipt_url']?.toString(),
      receiptPdfUrl:
          json['receipt_pdf_url']?.toString(),
      verificationError:
          json['verification_error']?.toString(),
    );
  }
}

class CorviaCreatePaymentResult {
  const CorviaCreatePaymentResult({
    required this.reference,
    required this.url,
    this.expiresAt,
  });

  final String reference;
  final Uri url;
  final DateTime? expiresAt;

  factory CorviaCreatePaymentResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final reference =
        json['reference']?.toString();

    final rawUrl =
        json['url']?.toString();

    if (reference == null ||
        reference.trim().isEmpty) {
      throw Exception(
        'Payment reference was not returned.',
      );
    }

    final uri =
        rawUrl == null ? null : Uri.tryParse(rawUrl);

    if (uri == null) {
      throw Exception(
        'Payment URL was not returned.',
      );
    }

    return CorviaCreatePaymentResult(
      reference: reference,
      url: uri,
      expiresAt:
          DateTime.tryParse(
            json['expires_at']?.toString() ?? '',
          )?.toLocal(),
    );
  }
}

class CorviaPayFastService {
  CorviaPayFastService({
    String? paymentPortalBaseUrl,
    SupabaseClient? supabase,
  })  : paymentPortalBaseUrl =
            paymentPortalBaseUrl ??
                const String.fromEnvironment(
                  'CORVIA_PAYMENT_PORTAL_URL',
                  defaultValue: '',
                ),
        _supabase =
            supabase ?? Supabase.instance.client;

  final String paymentPortalBaseUrl;
  final SupabaseClient _supabase;

  Future<CorviaCreatePaymentResult>
      createPayment({
    required String planCode,
    String? hospitalId,
  }) async {
    final response =
        await _supabase.functions.invoke(
      'create-payment',
      body: {
        'plan_code': planCode,
        if (hospitalId != null)
          'hospital_id': hospitalId,
      },
    );

    if (response.data is! Map) {
      throw Exception(
        'Corvia payment service returned an invalid response.',
      );
    }

    return CorviaCreatePaymentResult.fromJson(
      Map<String, dynamic>.from(
        response.data as Map,
      ),
    );
  }

  Future<CorviaPaymentCheckResult>
      checkPayment(
    String reference,
  ) async {
    final session =
        _supabase.auth.currentSession;

    if (session == null) {
      throw Exception(
        'You are not signed in.',
      );
    }

    final configuredBase =
        paymentPortalBaseUrl.trim();

    if (configuredBase.isEmpty) {
      throw Exception(
        'CORVIA_PAYMENT_PORTAL_URL is not configured in this build.',
      );
    }

    final base =
        configuredBase.replaceAll(
      RegExp(r'/+$'),
      '',
    );

    final uri = Uri.parse(
      '$base/api/corvia/payment-check/'
      '${Uri.encodeComponent(reference)}',
    );

    final response = await http.get(
      uri,
      headers: {
        'Authorization':
            'Bearer ${session.accessToken}',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Payment status could not be checked '
        '(${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(
      response.body,
    );

    if (decoded is! Map) {
      throw Exception(
        'Payment status response was invalid.',
      );
    }

    return CorviaPaymentCheckResult.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}