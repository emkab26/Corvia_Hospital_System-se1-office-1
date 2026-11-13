import 'support/ws4_access_fixture.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/dispatch/dispatch_dashboard.dart';
import 'package:mycorvia/services/emergency_dispatch_service.dart';
import 'package:mycorvia/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

DispatchEmergency incident(String id, {bool accepted = false}) =>
    DispatchEmergency(
      id: id,
      userId: 'sensitive-$id',
      status: accepted ? 'in_progress' : 'pending',
      createdAt: DateTime(2026, 10, 5, 9),
      acceptedAt: accepted ? DateTime(2026, 10, 5, 9, 1) : null,
      assignedDispatcherUserId: accepted ? 'dispatcher-test' : null,
    );

class QueueHarness {
  DispatchAccessLoader? accessLoader;
  int accessCalls = 0;

  final reads = <Completer<List<DispatchEmergency>>>[];
  final claims = <Completer<DispatchEmergency>>[];
  final claimedIds = <String>[];
  final signOut = Completer<void>();
  int signOutCalls = 0;

  Future<List<DispatchEmergency>> load() {
    final read = Completer<List<DispatchEmergency>>();
    reads.add(read);
    return read.future;
  }

  Future<DispatchEmergency> accept(String id) {
    claimedIds.add(id);
    final claim = Completer<DispatchEmergency>();
    claims.add(claim);
    return claim.future;
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: CorviaTheme.resolve(),
      home: EmergencyDispatchDashboard(
        accessLoader: () {
          accessCalls++;
          return accessLoader?.call() ?? Future.value(fixtureDispatchAccess());
        },
        incomingEmergencyLoader: load,
        incomingEmergencyAccepter: accept,
        onSignOut: () {
          signOutCalls++;
          return signOut.future;
        },
      ),
    ));
    await tester.pump();
  }

  Future<void> ready(WidgetTester tester) async {
    await mount(tester);
    reads.single.complete([incident('42')]);
    await tester.pumpAndSettle();
  }
}

VoidCallback claimCallback(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept emergency'))
    .onPressed!;

PostgrestException privateError(String code) => PostgrestException(
      message: 'private-message-marker',
      code: code,
      details: 'private-details-marker',
      hint: 'private-hint-marker',
    );

void guardedTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    var networkAttempts = 0;
    final diagnostics = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };
    try {
      await HttpOverrides.runZoned(() async {
        await body(tester);
        final visible = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
            .join('\n');
        expect(
            '$visible\n${diagnostics.join('\n')}', isNot(contains('private-')));
        await tester.pumpWidget(const SizedBox.shrink());
        // A Future timeout cannot be physically cancelled. Flush its deadline
        // after disposal; generation guards must prevent UI or network work.
        await tester.pump(const Duration(seconds: 15));
      }, createHttpClient: (_) {
        networkAttempts++;
        throw StateError('Unexpected network attempt');
      });
      expect(networkAttempts, 0);
    } finally {
      debugPrint = originalDebugPrint;
    }
  });
}

FilledButton claimButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Accept emergency'));

VoidCallback refreshCallback(WidgetTester tester) => tester
    .widget<IconButton>(find.byWidgetPredicate((widget) =>
        widget is IconButton &&
        widget.tooltip == 'Refresh incoming emergencies'))
    .onPressed!;

void main() {
  setUp(() {
    CorviaColors.setPalette(CorviaPalette.modern);
    CorviaColors.setBrightness(Brightness.light);
  });

  guardedTest('changed scope after read discards returned rows',
      (tester) async {
    final h = QueueHarness();
    await h.mount(tester);
    h.accessLoader = () async => fixtureDispatchAccess(
        organisationId: '00000000-0000-4000-8000-000000000003');
    h.reads.single.complete([incident('42')]);
    await tester.pumpAndSettle();
    expect(find.text('Emergency #42'), findsNothing);
    expect(find.text('No incoming emergencies'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(h.claims, isEmpty);
  });

  for (final lateError in [false, true]) {
    guardedTest(
        'claim timeout reconciles before late ${lateError ? 'error' : 'success'}',
        (tester) async {
      final h = QueueHarness();
      await h.ready(tester);
      final oldClaim = claimCallback(tester);
      oldClaim();
      await tester.pump();
      expect(h.claims, hasLength(1));
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not confirm whether'), findsOneWidget);
      expect(claimButton(tester).onPressed, isNull);
      oldClaim();
      expect(h.claims, hasLength(1));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      h.reads.last.complete([incident('42', accepted: true)]);
      await tester.pumpAndSettle();
      if (lateError) {
        h.claims.single.completeError(privateError('PGRST301'));
      } else {
        h.claims.single.complete(incident('99', accepted: true));
      }
      await tester.pumpAndSettle();
      expect(find.text('Emergency #42'), findsOneWidget);
      expect(find.text('Emergency #99'), findsNothing);
      expect(find.text('In Progress'), findsWidgets);
      expect(h.claims, hasLength(1));
    });
  }

  guardedTest('revocation while rows load is not an authorized empty queue',
      (tester) async {
    final h = QueueHarness();
    await h.mount(tester);
    h.accessLoader = () async => throw privateError('42501');
    h.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No incoming emergencies'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(h.claims, isEmpty);
  });

  for (final signOut in [false, true]) {
    guardedTest(
        'late pre-claim context after ${signOut ? 'sign-out' : 'disposal'} sends nothing',
        (tester) async {
      final h = QueueHarness();
      await h.ready(tester);
      final access = Completer<DispatchAccessContext>();
      h.accessLoader = () => access.future;
      claimCallback(tester)();
      await tester.pump();
      if (signOut) {
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
        await tester.pump();
        h.signOut.complete();
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      access.complete(fixtureDispatchAccess());
      await tester.pumpAndSettle();
      expect(h.claims, isEmpty);
      expect(find.text('Emergency #42'), findsNothing);
    });
  }

  guardedTest('access denial is not an authorized empty queue', (tester) async {
    final h = QueueHarness()
      ..accessLoader = () async => throw privateError('42501');
    await h.mount(tester);
    await tester.pumpAndSettle();
    expect(h.reads, isEmpty);
    expect(find.text('No incoming emergencies'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    h.accessLoader = () async => fixtureDispatchAccess();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    h.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No incoming emergencies'), findsOneWidget);
  });

  for (final code in ['42501', '503']) {
    guardedTest('failed access refresh $code clears protected state',
        (tester) async {
      final h = QueueHarness();
      await h.ready(tester);
      final oldClaim = claimCallback(tester);
      h.accessLoader = () async => throw privateError(code);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Emergency #42'), findsNothing);
      expect(find.text('No incoming emergencies'), findsNothing);
      oldClaim();
      await tester.pump(const Duration(seconds: 45));
      expect(h.reads, hasLength(1));
      expect(h.claims, isEmpty);
    });
  }

  guardedTest('read-only context loads queue but never grants claim',
      (tester) async {
    final h = QueueHarness()
      ..accessLoader = () async => fixtureDispatchAccess(canClaim: false);
    await h.ready(tester);
    expect(find.text('Emergency #42'), findsOneWidget);
    expect(claimButton(tester).onPressed, isNull);
    expect(h.claims, isEmpty);
  });

  guardedTest('revocation before claim prevents mutation', (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    h.accessLoader = () async => throw privateError('42501');
    claimCallback(tester)();
    await tester.pumpAndSettle();
    expect(h.claims, isEmpty);
    expect(find.text('Emergency #42'), findsNothing);
    expect(find.textContaining('No claim was sent'), findsOneWidget);
  });

  guardedTest('changed scope before claim requires fresh queue',
      (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    h.accessLoader = () async => fixtureDispatchAccess(
        organisationId: '00000000-0000-4000-8000-000000000003');
    claimCallback(tester)();
    await tester.pumpAndSettle();
    expect(h.claims, isEmpty);
    expect(find.text('Emergency #42'), findsNothing);
    expect(find.textContaining('Dispatch access changed'), findsOneWidget);
  });

  guardedTest('scope change clears old rows before replacement read finishes',
      (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    h.accessLoader = () async => fixtureDispatchAccess(
        organisationId: '00000000-0000-4000-8000-000000000003');
    refreshCallback(tester)();
    await tester.pump();
    expect(h.reads, hasLength(2));
    expect(find.text('Emergency #42'), findsNothing);
    h.reads.last.complete([incident('43')]);
    await tester.pumpAndSettle();
    expect(find.text('Emergency #43'), findsOneWidget);
  });

  for (final dispose in [false, true]) {
    guardedTest(
        'late access after ${dispose ? 'disposal' : 'timeout'} cannot load incidents',
        (tester) async {
      final access = Completer<DispatchAccessContext>();
      final h = QueueHarness()..accessLoader = () => access.future;
      await h.mount(tester);
      if (dispose) {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
      }
      access.complete(fixtureDispatchAccess());
      await tester.pumpAndSettle();
      expect(h.reads, isEmpty);
      expect(h.claims, isEmpty);
    });
  }

  guardedTest('late pre-claim access after timeout cannot submit claim',
      (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    final access = Completer<DispatchAccessContext>();
    h.accessLoader = () => access.future;
    claimCallback(tester)();
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    access.complete(fixtureDispatchAccess());
    await tester.pumpAndSettle();
    expect(h.claims, isEmpty);
    expect(find.text('Emergency #42'), findsNothing);
  });

  guardedTest('R21 regression: typed JWT read denial clears retained data',
      (tester) async {
    final harness = QueueHarness();
    await harness.ready(tester);
    final capturedClaim = claimCallback(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(harness.reads, hasLength(2));
    harness.reads.last.completeError(privateError('PGRST301'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency #42'), findsNothing);
    expect(find.textContaining('Patient account sensitive-42'), findsNothing);
    capturedClaim();
    await tester.pump();
    expect(harness.claims, isEmpty);
    await tester.pump(const Duration(seconds: 45));
    expect(harness.reads, hasLength(2));
    expect(find.text('No incoming emergencies'), findsNothing);
  });
  for (final entry in <String, Object>{
    'PGRST301': privateError('PGRST301'),
    'PGRST302': privateError('PGRST302'),
    'PGRST303': privateError('PGRST303'),
    'Postgrest 401': privateError('401'),
    'Postgrest 403': privateError('403'),
    'Postgrest 42501': privateError('42501'),
    'Auth 401':
        const AuthException('private-message-marker', statusCode: '401'),
    'Auth 403':
        const AuthException('private-message-marker', statusCode: '403'),
  }.entries) {
    for (final mutation in [false, true]) {
      guardedTest(
          '${entry.key} ${mutation ? 'claim' : 'read'} denial and recovery',
          (tester) async {
        final h = QueueHarness();
        await h.ready(tester);
        final captured = claimCallback(tester);
        if (mutation) {
          captured();
          await tester.pump();
          h.claims.single.completeError(entry.value);
        } else {
          refreshCallback(tester)();
          await tester.pump();
          h.reads.last.completeError(entry.value);
        }
        await tester.pumpAndSettle();
        expect(find.text('Emergency #42'), findsNothing);
        expect(
            find.textContaining('Patient account sensitive-42'), findsNothing);
        expect(find.text('No incoming emergencies'), findsNothing);
        expect(
            find.textContaining(mutation ? "Couldn't accept" : "Couldn't load"),
            findsOneWidget);
        expect(find.textContaining('Outdated'), findsOneWidget);
        expect(find.text('Queue read failed'), findsOneWidget);
        captured();
        final reads = h.reads.length;
        await tester.pump(const Duration(seconds: 45));
        expect(h.reads, hasLength(reads));
        expect(h.claims, hasLength(mutation ? 1 : 0));
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(h.reads, hasLength(reads + 1));
        captured();
        // Both empty and rows are authoritative recovery outcomes.
        h.reads.last.complete(mutation ? [] : [incident('42')]);
        await tester.pumpAndSettle();
        expect(find.textContaining('Outdated'), findsNothing);
        expect(find.text('Queue read succeeded'), findsOneWidget);
        captured();
        await tester.pump();
        expect(h.claims, hasLength(mutation ? 1 : 0));
        if (mutation) {
          expect(find.text('No incoming emergencies'), findsOneWidget);
        } else {
          expect(claimButton(tester).onPressed, isNotNull);
        }
        await tester.pump(const Duration(seconds: 15));
        expect(h.reads, hasLength(reads + 2));
      });
    }
  }

  for (final entry in <String, Object>{
    'PGRST300': privateError('PGRST300'),
    'unknown typed code': privateError('UNKNOWN'),
    'untyped JWT text': Exception('PGRST301 private-message-marker'),
    'transient server error': privateError('503'),
  }.entries) {
    for (final mutation in [false, true]) {
      guardedTest(
          '${entry.key} ${mutation ? 'claim' : 'read'} keeps read-only rows',
          (tester) async {
        final h = QueueHarness();
        await h.ready(tester);
        final captured = claimCallback(tester);
        if (mutation) {
          captured();
          await tester.pump();
          h.claims.single.completeError(entry.value);
        } else {
          refreshCallback(tester)();
          await tester.pump();
          h.reads.last.completeError(entry.value);
        }
        await tester.pumpAndSettle();
        expect(find.text('Emergency #42'), findsOneWidget);
        expect(find.textContaining('Outdated'), findsOneWidget);
        expect(claimButton(tester).onPressed, isNull);
        expect(find.text('No incoming emergencies'), findsNothing);
        if (mutation) {
          expect(
              find.textContaining('Could not confirm whether'), findsOneWidget);
        }
        captured();
        final reads = h.reads.length;
        await tester.pump(const Duration(seconds: 45));
        expect(h.reads, hasLength(reads));
        expect(h.claims, hasLength(mutation ? 1 : 0));
        await tester.tap(find.text('Try again'));
        await tester.pump();
        h.reads.last.complete([incident('42', accepted: mutation)]);
        await tester.pumpAndSettle();
        captured();
        await tester.pump();
        expect(h.claims, hasLength(mutation ? 1 : 0));
      });
    }
  }

  for (final empty in [false, true]) {
    guardedTest(
        'initial loading becomes authoritative ${empty ? 'empty' : 'rows'}',
        (tester) async {
      final h = QueueHarness();
      await h.mount(tester);
      expect(find.text('Not updated yet'), findsOneWidget);
      expect(find.text('No incoming emergencies'), findsNothing);
      expect(find.text('Accept emergency'), findsNothing);
      h.reads.single.complete(empty ? [] : [incident('42')]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Updated '), findsOneWidget);
      expect(find.text('No incoming emergencies'),
          empty ? findsOneWidget : findsNothing);
      if (!empty) expect(claimButton(tester).onPressed, isNotNull);
    });
  }

  for (final timeout in [false, true]) {
    guardedTest(
        'initial ${timeout ? 'timeout' : 'error'} needs explicit safe retry',
        (tester) async {
      final h = QueueHarness();
      await h.mount(tester);
      if (timeout) {
        await tester.pump(const Duration(seconds: 15));
      } else {
        h.reads.single.completeError(privateError('503'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Not updated yet'), findsOneWidget);
      expect(find.text('No incoming emergencies'), findsNothing);
      expect(find.textContaining("Couldn't load incoming emergencies."),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 45));
      expect(h.reads, hasLength(1));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      h.reads.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No incoming emergencies'), findsOneWidget);
      expect(find.textContaining('Updated '), findsOneWidget);
      if (timeout) {
        h.reads.first.complete([incident('99')]);
        await tester.pumpAndSettle();
        expect(find.text('Emergency #99'), findsNothing);
      }
    });
  }

  guardedTest(
      'manual refresh and poll ticks own one read and block stale claims',
      (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    final claim = claimCallback(tester);
    final refresh = refreshCallback(tester);
    await tester.pump(const Duration(seconds: 14));
    refresh();
    refresh();
    await tester.pump(const Duration(seconds: 2));
    expect(h.reads, hasLength(2));
    expect(claimButton(tester).onPressed, isNull);
    expect(find.textContaining('Refreshing'), findsWidgets);
    claim();
    expect(h.claims, isEmpty);
    h.reads.last.complete([incident('42')]);
    await tester.pumpAndSettle();
    claim(); // Obsolete even though the same incident is pending again.
    refresh();
    expect(h.claims, isEmpty);
    expect(h.reads, hasLength(2));
    final nextRefresh = refreshCallback(tester);
    await tester.pump(const Duration(seconds: 15));
    nextRefresh(); // A queued manual click cannot overlap the new poll.
    expect(h.reads, hasLength(3));
    h.reads.last.complete([incident('43')]);
    await tester.pumpAndSettle();
    expect(find.text('Emergency #43'), findsOneWidget);
    expect(find.text('Emergency #42'), findsNothing);
  });

  for (final oldError in [false, true]) {
    guardedTest(
        'timed-out ${oldError ? 'error' : 'success'} cannot overwrite recovery or claim',
        (tester) async {
      final h = QueueHarness();
      await h.ready(tester);
      refreshCallback(tester)();
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      final obsolete = h.reads.last;
      expect(claimButton(tester).onPressed, isNull);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      h.reads.last.complete([incident('43')]);
      await tester.pumpAndSettle();
      claimCallback(tester)();
      await tester.pump();
      h.claims.single.complete(incident('43', accepted: true));
      await tester.pumpAndSettle();
      if (oldError) {
        obsolete.completeError(privateError('PGRST303'));
      } else {
        obsolete.complete([incident('42')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Emergency #43'), findsOneWidget);
      expect(find.text('Emergency #42'), findsNothing);
      expect(find.text('In Progress'), findsWidgets);
      expect(find.textContaining('Outdated'), findsNothing);
      expect(h.claimedIds, ['43']);
    });
  }

  guardedTest('claim is serialized, authoritative and never optimistic',
      (tester) async {
    final h = QueueHarness();
    await h.ready(tester);
    final claim = claimCallback(tester);
    final refresh = refreshCallback(tester);
    claim();
    claim();
    refresh();
    await tester.pump();
    expect(h.claims, hasLength(1));
    expect(h.reads, hasLength(1));
    expect(find.text('In Progress'), findsNothing);
    expect(find.text('Accepted at 09:01'), findsNothing);
    // Complete within the new bounded claim window. Separate timeout tests
    // cover unknown outcomes, stopped polling and ignored late responses.
    await tester.pump(const Duration(seconds: 14));
    expect(h.reads, hasLength(1));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Accepting emergency...'))
            .onPressed,
        isNull);
    h.claims.single.complete(incident('42', accepted: true));
    await tester.pumpAndSettle();
    expect(find.text('In Progress'), findsWidgets);
    expect(find.text('Accepted at 09:01'), findsOneWidget);
    claim();
    expect(h.claims, hasLength(1));
    await tester.pump(const Duration(seconds: 15));
    expect(h.reads, hasLength(2));
  });

  guardedTest('callback checks the currently selected pending incident',
      (tester) async {
    final h = QueueHarness();
    await h.mount(tester);
    h.reads.single.complete([incident('42'), incident('43')]);
    await tester.pumpAndSettle();
    final oldSelection = claimCallback(tester);
    await tester.tap(find.text('Emergency #43'));
    await tester.pump();
    oldSelection();
    expect(h.claims, isEmpty);
    claimCallback(tester)();
    await tester.pump(); // Claim follows asynchronous server access validation.
    expect(h.claimedIds, ['43']);
    h.claims.single.complete(incident('43', accepted: true));
    await tester.pumpAndSettle();
  });

  for (final outcome in ['success', 'transient failure', 'denial']) {
    guardedTest('claim conflict reconciliation: $outcome', (tester) async {
      final h = QueueHarness();
      await h.ready(tester);
      final oldClaim = claimCallback(tester);
      oldClaim();
      await tester.pump();
      h.claims.single.completeError(const PostgrestException(
        message:
            'This emergency has already been accepted. private-message-marker',
        code: 'P0001',
      ));
      await tester.pump();
      await tester.pump();
      expect(h.reads, hasLength(2));
      expect(claimButton(tester).onPressed, isNull);
      expect(
          find.textContaining('The queue has been refreshed.'), findsNothing);
      if (outcome == 'success') {
        h.reads.last.complete([incident('42', accepted: true)]);
      } else {
        h.reads.last.completeError(
            privateError(outcome == 'denial' ? 'PGRST302' : '503'));
      }
      await tester.pumpAndSettle();
      oldClaim();
      expect(h.claims, hasLength(1));
      if (outcome == 'success') {
        expect(find.textContaining('The queue has been refreshed.'),
            findsOneWidget);
        expect(find.text('In Progress'), findsWidgets);
      } else {
        expect(
            find.textContaining('The queue has been refreshed.'), findsNothing);
        expect(find.textContaining('Outdated'), findsOneWidget);
        if (outcome == 'denial') {
          expect(find.text('Emergency #42'), findsNothing);
        } else {
          expect(claimButton(tester).onPressed, isNull);
        }
        await tester.pump(const Duration(seconds: 45));
        expect(h.reads, hasLength(2));
      }
    });
  }

  for (final mutation in [false, true]) {
    for (final lateError in [false, true]) {
      guardedTest(
          'dispose during ${mutation ? 'claim' : 'read'} ignores late ${lateError ? 'error' : 'success'}',
          (tester) async {
        final h = QueueHarness();
        await h.ready(tester);
        final claim = claimCallback(tester);
        final refresh = refreshCallback(tester);
        if (mutation) {
          claim();
        } else {
          refresh();
        }
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        if (mutation) {
          if (lateError) {
            h.claims.single.completeError(privateError('PGRST301'));
          } else {
            h.claims.single.complete(incident('42', accepted: true));
          }
        } else {
          if (lateError) {
            h.reads.last.completeError(privateError('PGRST301'));
          } else {
            h.reads.last.complete([incident('42')]);
          }
        }
        claim();
        refresh();
        await tester.pump(const Duration(seconds: 45));
        expect(h.reads, hasLength(mutation ? 1 : 2));
        expect(h.claims, hasLength(mutation ? 1 : 0));
        expect(tester.takeException(), isNull);
      });
    }
    for (final failedSignOut in [false, true]) {
      guardedTest(
          'sign-out during ${mutation ? 'claim' : 'read'} remains closed after ${failedSignOut ? 'failure' : 'success'}',
          (tester) async {
        final h = QueueHarness();
        await h.ready(tester);
        final claim = claimCallback(tester);
        final refresh = refreshCallback(tester);
        if (mutation) {
          claim();
        } else {
          refresh();
        }
        await tester.pump();
        await tester.tap(find.text('Sign out'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(h.signOutCalls, 1);
        expect(find.text('Emergency #42'), findsNothing);
        if (mutation) {
          h.claims.single.complete(incident('42', accepted: true));
        } else {
          h.reads.last.complete([incident('42')]);
        }
        if (failedSignOut) {
          h.signOut.completeError(privateError('503'));
        } else {
          h.signOut.complete();
        }
        await tester.pumpAndSettle();
        claim();
        refresh();
        await tester.pump(const Duration(seconds: 45));
        expect(find.text('Emergency #42'), findsNothing);
        expect(h.reads, hasLength(mutation ? 1 : 2));
        expect(h.claims, hasLength(mutation ? 1 : 0));
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('main and auth route source target the widget exercised above', () {
    // Inspect wiring without importing/launching configured main or auth clients.
    final mainSource = File('lib/main.dart').readAsStringSync();
    final authSource = File('lib/auth/auth_gate.dart').readAsStringSync();
    expect(mainSource, isNot(contains('const EmergencyDispatchDashboard()')));
    expect(mainSource, contains("'/dispatch':"));
    expect(mainSource, contains('const AuthGate()'));
    expect(mainSource, contains('const DispatchEntryRedirect()'));
    expect(authSource,
        contains("import '../pages/dispatch/dispatch_dashboard.dart';"));
    expect(authSource, contains('return EmergencyDispatchDashboard('));
  });
}
