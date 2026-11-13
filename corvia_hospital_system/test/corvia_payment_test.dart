import 'package:flutter_test/flutter_test.dart';

import 'package:mycorvia/services/corvia_payfast_service.dart';
import 'package:mycorvia/services/corvia_subscription_service.dart';

void main() {
  group('Corvia subscription entitlements', () {
    test(
      'basic plan keeps core features but does not grant full access',
      () {
        const entitlements = CorviaEntitlements(
          hospitalId: 'hospital-1',
          plan: 'basic',
          subscriptionStatus: 'basic',
          fullAccess: false,
          features: {
            'billing': true,
            'patient_management': true,
            'medical_records': true,
            'appointments': true,
            'emergency_access': true,
            'blood_bank': false,
            'visitor_management': false,
            'telehealth': false,
          },
        );

        expect(
          entitlements.plan,
          'basic',
        );

        expect(
          entitlements.fullAccess,
          isFalse,
        );

        expect(
          entitlements.hasFeature(
            'billing',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'patient_management',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'emergency_access',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'blood_bank',
          ),
          isFalse,
        );

        expect(
          entitlements.hasFeature(
            'telehealth',
          ),
          isFalse,
        );
      },
    );

    test(
      'full plan grants premium features',
      () {
        const entitlements = CorviaEntitlements(
          hospitalId: 'hospital-1',
          plan: 'full',
          subscriptionStatus: 'active',
          fullAccess: true,
          features: {
            'billing': true,
            'patient_management': true,
            'medical_records': true,
            'appointments': true,
            'emergency_access': true,
            'blood_bank': true,
            'visitor_management': true,
            'hospital_transfers': true,
            'telehealth': true,
            'advanced_reports': true,
            'ems_fleet': true,
            'paramedic_workspace': true,
          },
        );

        expect(
          entitlements.plan,
          'full',
        );

        expect(
          entitlements.subscriptionStatus,
          'active',
        );

        expect(
          entitlements.fullAccess,
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'blood_bank',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'visitor_management',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'hospital_transfers',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'ems_fleet',
          ),
          isTrue,
        );

        expect(
          entitlements.hasFeature(
            'paramedic_workspace',
          ),
          isTrue,
        );
      },
    );

    test(
      'unknown feature is denied by default',
      () {
        const entitlements = CorviaEntitlements(
          hospitalId: 'hospital-1',
          plan: 'basic',
          subscriptionStatus: 'basic',
          fullAccess: false,
          features: {},
        );

        expect(
          entitlements.hasFeature(
            'does_not_exist',
          ),
          isFalse,
        );
      },
    );
  });

  group('Corvia payment records', () {
    test(
      'Supabase payment-attempt rows map to the monitor contract',
      () {
        final payment = CorviaPaymentRecord.fromJson(
          {
            'id': '6d9cc6f5-3bc5-45cb-bc31-e37fd80527ee',
            'status': 'paid',
            'amount_cents': 14900,
            'currency': 'ZAR',
            'plan_code': 'monthly',
            'plan_name': 'Everyday care',
            'environment': 'sandbox',
            'provider_payment_id': 'PF-123',
            'receipt_number': 'COR-123',
            'duplicate_count': 2,
            'created_at': '2026-10-09T08:00:00Z',
            'paid_at': '2026-10-09T08:05:00Z',
          },
        );

        expect(payment.reference, '6d9cc6f5-3bc5-45cb-bc31-e37fd80527ee');
        expect(payment.amountDue, 149.00);
        expect(payment.verificationStatus, 'verified');
        expect(payment.isPaid, isTrue);
        expect(payment.planName, 'Everyday care');
        expect(payment.receiptNumber, 'COR-123');
        expect(payment.duplicateCount, 2);
      },
    );

    test(
      'review-required Supabase rows need staff attention',
      () {
        final payment = CorviaPaymentRecord.fromJson(
          {
            'id': '37bc81ef-b750-48ce-858d-73d1742c2161',
            'status': 'pending',
            'amount_cents': 149900,
            'currency': 'ZAR',
            'review_required': true,
            'reason_code': 'amount_mismatch',
            'review_state': 'open',
            'review_reason': 'Confirm the amount with PayFast.',
            'created_at': '2026-10-09T08:00:00Z',
          },
        );

        expect(payment.amountDue, 1499.00);
        expect(payment.needsAttention, isTrue);
        expect(payment.verificationStatus, 'amount_mismatch');
        expect(payment.reviewState, 'open');
      },
    );

    test(
      'verified paid payment is treated as paid',
      () {
        final payment = CorviaPaymentRecord(
          reference: 'CORVIA-TEST-001',
          status: 'paid',
          verificationStatus: 'verified',
          amountDue: 1500.00,
          amountReceived: 1500.00,
          currency: 'ZAR',
          providerPaymentId: 'PF-12345',
          createdAt: DateTime.utc(
            2026,
            10,
            9,
            8,
            0,
          ),
          paidAt: DateTime.utc(
            2026,
            10,
            9,
            8,
            5,
          ),
        );

        expect(
          payment.isPaid,
          isTrue,
        );

        expect(
          payment.isPending,
          isFalse,
        );

        expect(
          payment.needsAttention,
          isFalse,
        );

        expect(
          payment.amountDue,
          1500.00,
        );

        expect(
          payment.amountReceived,
          1500.00,
        );
      },
    );

    test(
      'pending payment is not paid',
      () {
        final payment = CorviaPaymentRecord(
          reference: 'CORVIA-TEST-002',
          status: 'pending',
          verificationStatus: 'not_checked',
          amountDue: 1500.00,
          currency: 'ZAR',
          createdAt: DateTime.utc(
            2026,
            10,
            9,
            8,
            0,
          ),
        );

        expect(
          payment.isPaid,
          isFalse,
        );

        expect(
          payment.isPending,
          isTrue,
        );

        expect(
          payment.needsAttention,
          isFalse,
        );
      },
    );

    test(
      'review-required payment needs attention',
      () {
        final payment = CorviaPaymentRecord(
          reference: 'CORVIA-TEST-003',
          status: 'review_required',
          verificationStatus: 'amount_mismatch',
          amountDue: 1500.00,
          amountReceived: 1000.00,
          currency: 'ZAR',
          verificationError: 'Expected R1500.00 but received R1000.00.',
          createdAt: DateTime.utc(
            2026,
            10,
            9,
            8,
            0,
          ),
        );

        expect(
          payment.isPaid,
          isFalse,
        );

        expect(
          payment.needsAttention,
          isTrue,
        );
      },
    );

    test(
      'signature mismatch needs attention',
      () {
        final payment = CorviaPaymentRecord(
          reference: 'CORVIA-TEST-004',
          status: 'pending',
          verificationStatus: 'signature_mismatch',
          amountDue: 1500.00,
          currency: 'ZAR',
          createdAt: DateTime.utc(
            2026,
            10,
            9,
            8,
            0,
          ),
        );

        expect(
          payment.isPaid,
          isFalse,
        );

        expect(
          payment.needsAttention,
          isTrue,
        );
      },
    );
  });

  group('PayFast payment check model', () {
    test(
      'verified response is considered paid',
      () {
        final result = CorviaPaymentCheckResult(
          reference: 'CORVIA-TEST-005',
          status: 'paid',
          verificationStatus: 'verified',
          amountDue: 1500.00,
          amountReceived: 1500.00,
          currency: 'ZAR',
          providerPaymentId: 'PF-555',
          paidAt: DateTime.utc(
            2026,
            10,
            9,
            9,
            0,
          ),
        );

        expect(
          result.isPaid,
          isTrue,
        );

        expect(
          result.needsAttention,
          isFalse,
        );
      },
    );

    test(
      'review-required response is not accepted as paid',
      () {
        const result = CorviaPaymentCheckResult(
          reference: 'CORVIA-TEST-006',
          status: 'review_required',
          verificationStatus: 'amount_mismatch',
          amountDue: 1500.00,
          amountReceived: 1000.00,
          currency: 'ZAR',
          verificationError: 'Payment amount mismatch.',
        );

        expect(
          result.isPaid,
          isFalse,
        );

        expect(
          result.needsAttention,
          isTrue,
        );
      },
    );
  });

  group('Corvia checkout response', () {
    test(
      'valid checkout response parses reference and URL',
      () {
        final result = CorviaCreatePaymentResult.fromJson(
          {
            'reference': 'CORVIA-CHECKOUT-001',
            'url': 'https://pay.corvia.co.za/checkout/test-token',
            'expires_at': '2026-10-09T12:00:00Z',
          },
        );

        expect(
          result.reference,
          'CORVIA-CHECKOUT-001',
        );

        expect(
          result.url.scheme,
          'https',
        );

        expect(
          result.url.host,
          'pay.corvia.co.za',
        );

        expect(
          result.expiresAt,
          isNotNull,
        );
      },
    );

    test(
      'checkout response requires a reference',
      () {
        expect(
          () => CorviaCreatePaymentResult.fromJson(
            {
              'url': 'https://pay.corvia.co.za/checkout/test-token',
            },
          ),
          throwsException,
        );
      },
    );

    test(
      'checkout response requires a payment URL',
      () {
        expect(
          () => CorviaCreatePaymentResult.fromJson(
            {
              'reference': 'CORVIA-CHECKOUT-002',
            },
          ),
          throwsException,
        );
      },
    );
  });
}
