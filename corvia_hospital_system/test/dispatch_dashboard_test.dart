import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/pages/patient/dispatch.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Rows = List<Map<String, dynamic>>;

// Deliberately permits callbacks after cancel to exercise generation guards.
// Cancellation completion is independent of callback delivery and widget time.
class _Feed extends Stream<_Rows> {
  void Function(_Rows)? data;
  Function? error;
  void Function()? done;
  Completer<void>? cancellation;
  Object? listenFailure;
  Object? cancellationFailure;
  bool throwOnCancel = false;
  void Function(_Feed)? duringListen;
  int listens = 0;
  int cancels = 0;
  bool active = false;

  @override
  StreamSubscription<_Rows> listen(
    void Function(_Rows)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (listenFailure != null) throw listenFailure!;
    listens++;
    active = true;
    data = onData;
    error = onError;
    done = onDone;
    duringListen?.call(this);
    return _Subscription(this);
  }

  void emit(_Rows rows) => data!(rows);
  void fail(Object value) => Function.apply(error!, [value]);
  void close() => done!();
}

class _Subscription implements StreamSubscription<_Rows> {
  _Subscription(this.feed);
  final _Feed feed;

  @override
  Future<void> cancel() {
    feed.cancels++;
    if (feed.throwOnCancel) throw StateError('private cancellation details');
    return _finishCancel();
  }

  Future<void> _finishCancel() async {
    if (feed.cancellationFailure != null) throw feed.cancellationFailure!;
    await feed.cancellation?.future;
    feed.active = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _harnesses = <_Harness>[];

class _Harness {
  _Harness() {
    _harnesses.add(this);
  }
  final feeds = <_Feed>[];
  final writes = <(String, String)>[];
  Completer<void>? writeCompletion;
  Object? factoryFailure;
  Object? writeFailure;
  _Feed Function()? nextFeed;
  int factoryCalls = 0;
  int overlappingSubscriptions = 0;

  Stream<_Rows> factory() {
    factoryCalls++;
    // This also fails if a replacement is created before delayed cancellation.
    if (feeds.any((feed) => feed.active)) overlappingSubscriptions++;
    if (factoryFailure != null) throw factoryFailure!;
    final feed = nextFeed?.call() ?? _Feed();
    feeds.add(feed);
    return feed;
  }

  Future<void> write(String id, String status) async {
    writes.add((id, status));
    if (writeFailure != null) throw writeFailure!;
    await writeCompletion?.future;
  }

  Widget widget() => MaterialApp(
        home: DispatchDashboard(
          incidentStreamFactory: factory,
          statusWriter: write,
        ),
      );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(widget());
    await tester.pump();
  }
}

_Rows _rows([String user = 'patient-a']) => [
      {
        'id': 17,
        'user_id': user,
        'latitude': -25.7,
        'longitude': 28.2,
        'status': 'pending',
        'created_at': '2026-10-02T10:00:00Z',
      },
    ];

final _refresh = find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Refresh incidents',
);
final _resolved = find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Mark as Resolved',
);
final _progress = find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Mark as In Progress',
);

void _expectActionsDisabled(WidgetTester tester) {
  for (final button in tester.widgetList<IconButton>(
    find.byWidgetPredicate((widget) =>
        widget is IconButton &&
        const ['Mark as Resolved', 'Mark as In Progress']
            .contains(widget.tooltip)),
  )) {
    expect(button.onPressed, isNull);
  }
}

const _jwtCodes = ['PGRST301', 'PGRST302', 'PGRST303'];
const _jwtSessionReason =
    'Your session could not be verified. Please sign in and try again.';

PostgrestException _jwtError(String code) {
  final error = PostgrestException.fromJson({
    'code': code,
    'message': 'opaque-private-message',
    'details': 'opaque-private-details',
    'hint': 'opaque-private-hint',
  }, code: 401);
  expect(error.code, code); // The JSON code wins over the HTTP fallback.
  return error;
}

void _expectNoIncidentRows() {
  expect(find.byType(ListTile), findsNothing);
  for (final label in ['User: ', 'Lat: ', 'Status: ', 'Time: ']) {
    expect(find.textContaining(label), findsNothing);
  }
}

void _expectNoPrivateDiagnostics() {
  for (final marker in [
    'opaque-private-message',
    'opaque-private-details',
    'opaque-private-hint',
  ]) {
    expect(find.textContaining(marker), findsNothing);
  }
}

// Flutter's default HTTP override returns 400; here even a caught attempted
// connection fails the test. No Supabase initialization or .env is needed.
void _widgetTest(
  String name,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(name, (tester) async {
    _harnesses.clear();
    var networkAttempts = 0;
    await HttpOverrides.runZoned(
      () async {
        try {
          await body(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          expect(networkAttempts, 0, reason: 'Unexpected network activity');
          for (final harness in _harnesses) {
            expect(harness.overlappingSubscriptions, 0,
                reason: 'Overlapping application subscriptions');
          }
        }
      },
      createHttpClient: (_) {
        networkAttempts++;
        throw StateError('Network is forbidden in dispatch widget tests');
      },
    );
  });
}

void main() {
  test('default const route construction is preserved', () {
    const page = DispatchDashboard();
    expect(page.incidentStreamFactory, isNull);
    expect(page.statusWriter, isNull);
  });

  _widgetTest(
      'Q1 Q2 mount/rebuild owns one feed; data controls loading and order',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    expect(h.factoryCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No incidents found.'), findsNothing);
    await tester.pumpWidget(h.widget());
    await tester.pump();
    expect(h.factoryCalls, 1);
    final rows = [..._rows('newest'), ..._rows('older')];
    rows[1]['id'] = 18;
    h.feeds.single.emit(rows);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Lat: -25.7, Lng: 28.2'), findsNWidgets(2));
    expect(find.text('Status: pending'), findsNWidgets(2));
    expect(find.text('Time: 2026-10-02T10:00:00Z'), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('User: newest')).dy,
        lessThan(tester.getTopLeft(find.text('User: older')).dy));
    // Mutating the SDK's previously emitted map must not alter cached rows.
    rows[0]['user_id'] = 'changed externally';
    await tester.pumpWidget(h.widget());
    expect(find.text('User: newest'), findsOneWidget);
  });

  _widgetTest('Q2 successful empty and original missing-field fallbacks',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.feeds.single.emit([]);
    await tester.pump();
    expect(find.text('No incidents found.'), findsOneWidget);
    h.feeds.single.emit([{}]);
    await tester.pump();
    expect(find.text('User: Unknown'), findsOneWidget);
    expect(find.text('Lat: N/A, Lng: N/A'), findsOneWidget);
    expect(find.text('Status: unknown'), findsOneWidget);
    expect(find.text('Time: N/A'), findsOneWidget);
    _expectActionsDisabled(tester);
    expect(h.writes, isEmpty);
  });

  for (final kind in [
    'error',
    'close',
    'factory',
    'listen',
    'sync error',
    'sync close'
  ]) {
    _widgetTest('Q3 initial $kind shows safe error and Retry', (tester) async {
      final h = _Harness();
      final secret = StateError('private_table token.secret incident-17');
      if (kind == 'factory') h.factoryFailure = secret;
      if (kind == 'listen') {
        h.nextFeed = () => _Feed()..listenFailure = secret;
      }
      if (kind.startsWith('sync')) {
        h.nextFeed = () => _Feed()
          ..duringListen =
              (feed) => kind == 'sync error' ? feed.fail(secret) : feed.close();
      }
      await h.mount(tester);
      if (kind == 'error') h.feeds.single.fail(secret);
      if (kind == 'close') h.feeds.single.close();
      await tester.pump();
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No incidents found.'), findsNothing);
      expect(find.textContaining('private_table'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 16));
      expect(h.factoryCalls, 1); // Explicit retry only.
    });
  }

  _widgetTest('Q4 15-second timeout terminates feed; Retry has its own timer',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Error'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('took too long'), findsOneWidget);
    expect(h.feeds.first.cancels, 1);
    h.feeds.first.emit(_rows('late'));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(h.feeds.length, 2);
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Error'), findsNothing);
    h.feeds.last.emit(_rows('current'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('User: current'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
  });

  _widgetTest(
      'Q4 cancel old timer during early refresh; new timeout stays bounded',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(_refresh);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Error'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Error'), findsOneWidget);
    expect(h.feeds.length, 2);
  });

  for (final close in [false, true]) {
    for (final empty in [false, true]) {
      _widgetTest(
          'Q5 ${close ? 'closure' : 'failure'} after ${empty ? 'empty' : 'rows'}',
          (tester) async {
        final h = _Harness();
        await h.mount(tester);
        h.feeds.single.emit(empty ? [] : _rows());
        await tester.pump();
        if (close) {
          h.feeds.single.close();
        } else {
          h.feeds.single.fail(Exception('private_table secret'));
        }
        await tester.pump();
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No incidents found.'), findsNothing);
        expect(find.text('User: patient-a'),
            empty ? findsNothing : findsOneWidget);
        expect(find.textContaining('may be outdated'),
            empty ? findsNothing : findsOneWidget);
        _expectActionsDisabled(tester);
        if (!empty) await tester.tap(_resolved);
        expect(h.writes, isEmpty);
      });
    }
  }

  final accessErrors = <Object>[
    const AuthException('private_table token.secret', statusCode: '401'),
    const AuthException('private_table token.secret', statusCode: '403'),
    const PostgrestException(
        message: 'private_table token.secret', code: '401'),
    const PostgrestException(
        message: 'private_table token.secret', code: '403'),
    const PostgrestException(
        message: 'private_table token.secret', code: '42501'),
  ];
  for (var index = 0; index < accessErrors.length; index++) {
    _widgetTest('Q6 typed access failure $index clears sensitive rows',
        (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.feeds.single.emit(_rows());
      await tester.pump();
      h.feeds.single.fail(accessErrors[index]);
      await tester.pump();
      expect(find.text('User: patient-a'), findsNothing);
      expect(
          find.textContaining(
              index == 0 || index == 2 ? 'session has expired' : 'permission'),
          findsOneWidget);
      expect(find.textContaining('token.secret'), findsNothing);
      expect(find.textContaining('private_table'), findsNothing);
      expect(find.text('No incidents found.'), findsNothing);
    });
  }

  _widgetTest(
      'Q7 Q8 Q9 delayed cancel coalesces requests and rejects all old callbacks',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final old = h.feeds.single;
    old.emit(_rows());
    await tester.pump();
    old.cancellation = Completer<void>();
    final refreshCallback = tester.widget<IconButton>(_refresh).onPressed!;
    refreshCallback();
    refreshCallback();
    refreshCallback();
    await tester.pump();
    expect(h.factoryCalls, 1);
    expect(old.cancels, 1);
    expect(find.textContaining('Refreshing incident queue'), findsOneWidget);
    expect(find.text('User: patient-a'), findsOneWidget);
    _expectActionsDisabled(tester);
    old.emit(_rows('obsolete'));
    old.fail(accessErrors.first);
    old.close();
    await tester.pump();
    expect(find.text('User: patient-a'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    old.cancellation!.complete();
    await tester.pump();
    expect(h.factoryCalls, 2);
    h.feeds.last.emit(_rows('replacement'));
    await tester.pump();
    old.emit(_rows('obsolete'));
    old.fail(accessErrors.first);
    old.close();
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('User: replacement'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    expect(find.textContaining('outdated'), findsNothing);
  });

  _widgetTest(
      'Q7 cancellation failure prevents overlap; explicit Retry cancels again',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final old = h.feeds.single;
    old.emit(_rows());
    old.cancellationFailure = StateError('private cancellation detail');
    await tester.tap(_refresh);
    await tester.pump();
    expect(h.factoryCalls, 1);
    expect(find.text('Error'), findsOneWidget);
    expect(find.textContaining('private cancellation'), findsNothing);
    old.cancellationFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(h.factoryCalls, 2);
    h.feeds.last.emit([]);
    await tester.pump();
    expect(find.text('No incidents found.'), findsOneWidget);
  });

  _widgetTest('Q7 Q9 Retry after failure replaces rows with successful empty',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.feeds.single.emit(_rows());
    h.feeds.single.cancellation = Completer<void>();
    h.feeds.single.fail(Exception('unknown'));
    await tester.pump();
    final retry = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(h.factoryCalls, 1);
    h.feeds.single.cancellation!.complete();
    await tester.pump();
    expect(h.factoryCalls, 2);
    expect(h.feeds.length, 2);
    h.feeds.last.emit([]);
    await tester.pump();
    expect(find.text('No incidents found.'), findsOneWidget);
    expect(find.text('User: patient-a'), findsNothing);
    expect(find.text('Error'), findsNothing);
    expect(find.textContaining('outdated'), findsNothing);
    expect(h.writes, isEmpty);
  });

  _widgetTest('Q8 disposal invalidates delayed restart, callbacks and timer',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final old = h.feeds.single;
    old.cancellation = Completer<void>();
    await tester.tap(_refresh);
    await tester.pumpWidget(const SizedBox.shrink());
    old.emit(_rows());
    old.fail(Exception('late'));
    old.close();
    old.cancellation!.complete();
    await tester.pump(const Duration(seconds: 30));
    expect(h.factoryCalls, 1);
    expect(old.cancels, 1);
    expect(tester.takeException(), isNull);
  });

  _widgetTest('Q8 initial disposal cancels active first-event timer',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(h.feeds.single.cancels, 1);
    expect(h.factoryCalls, 1);
    expect(tester.takeException(), isNull);
  });

  _widgetTest(
      'Q10 Q11 one write in flight; exact ID/status; success refreshes without optimism',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    expect(h.writes, isEmpty);
    h.feeds.single.emit(_rows());
    await tester.pump();
    h.writeCompletion = Completer<void>();
    final action = tester.widget<IconButton>(_resolved).onPressed!;
    action();
    action();
    await tester.pump();
    expect(h.writes, [('17', 'resolved')]);
    _expectActionsDisabled(tester);
    expect(find.text('Status: pending'), findsOneWidget);
    expect(h.factoryCalls, 1);
    h.writeCompletion!.complete();
    await tester.pump();
    expect(h.factoryCalls, 2);
    _expectActionsDisabled(tester);
    expect(find.text('Status update request completed.'), findsOneWidget);
    h.feeds.last.emit(_rows());
    await tester.pump();
    h.writeCompletion = null;
    await tester.tap(_progress);
    await tester.pump();
    expect(h.writes, [('17', 'resolved'), ('17', 'in_progress')]);
    expect(h.factoryCalls, 3);
    h.feeds.last.emit([]);
    await tester.pump();
  });

  _widgetTest(
      'Q11 successful write plus failed refresh remains a read error; Retry never writes',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.feeds.single.emit(_rows());
    await tester.pump();
    await tester.tap(_resolved);
    await tester.pump();
    h.feeds.last.fail(Exception('private refresh secret'));
    await tester.pump();
    expect(find.text('Status update request completed.'), findsOneWidget);
    expect(find.textContaining("Couldn't refresh the incident queue."),
        findsOneWidget);
    expect(find.textContaining("Couldn't update the incident status."),
        findsNothing);
    _expectActionsDisabled(tester);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    h.feeds.last.emit([]);
    await tester.pump();
    expect(h.writes, [('17', 'resolved')]);
    expect(find.text('No incidents found.'), findsOneWidget);
  });

  _widgetTest('Q11 mutation failure is separately safe and never auto-retries',
      (tester) async {
    final h = _Harness()
      ..writeFailure = Exception('private_table token.secret');
    await h.mount(tester);
    h.feeds.single.emit(_rows());
    await tester.pump();
    await tester.tap(_progress);
    await tester.pump();
    expect(find.textContaining("Couldn't update the incident status."),
        findsOneWidget);
    expect(find.textContaining('token.secret'), findsNothing);
    expect(find.text('Error'), findsNothing);
    expect(h.factoryCalls, 1);
    expect(h.writes, [('17', 'in_progress')]);
    h.feeds.single.fail(Exception('read failure'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    h.feeds.last.emit(_rows());
    await tester.pump();
    expect(h.writes.length, 1);
  });

  _widgetTest('Q6 mutation access denial also clears retained rows',
      (tester) async {
    final h = _Harness()..writeFailure = accessErrors.last;
    await h.mount(tester);
    h.feeds.single.emit(_rows());
    await tester.pump();
    await tester.tap(_resolved);
    await tester.pump();
    expect(find.text('User: patient-a'), findsNothing);
    expect(find.text('Error'), findsOneWidget);
    expect(find.textContaining('token.secret'), findsNothing);
  });

  for (final fails in [false, true]) {
    _widgetTest(
        'Q8 late mutation ${fails ? 'failure' : 'success'} after disposal does nothing',
        (tester) async {
      final h = _Harness()..writeCompletion = Completer<void>();
      await h.mount(tester);
      h.feeds.single.emit(_rows());
      await tester.pump();
      await tester.tap(_resolved);
      await tester.pumpWidget(const SizedBox.shrink());
      if (fails) {
        h.writeCompletion!.completeError(Exception('late private error'));
      } else {
        h.writeCompletion!.complete();
      }
      await tester.pump(const Duration(seconds: 20));
      expect(h.factoryCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  _widgetTest(
      'Q12 real asynchronous controller stream also works without initialization',
      (tester) async {
    final controller = StreamController<_Rows>();
    await tester.pumpWidget(MaterialApp(
      home: DispatchDashboard(
        incidentStreamFactory: () => controller.stream,
        statusWriter: (id, status) async => fail('Unexpected status write'),
      ),
    ));
    await tester.pump();
    controller.add(_rows());
    await tester.pump();
    expect(find.text('User: patient-a'), findsOneWidget);
    unawaited(controller.close());
    await tester.pump();
    expect(find.text('Error'), findsOneWidget);
  });

  _widgetTest('Q7 synchronous cancellation failure prevents replacement',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final old = h.feeds.single..throwOnCancel = true;
    await tester.tap(_refresh);
    await tester.pump();
    expect(h.factoryCalls, 1);
    expect(find.text('Error'), findsOneWidget);
    expect(find.textContaining('private cancellation'), findsNothing);
    old.throwOnCancel = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(h.factoryCalls, 2);
    h.feeds.last.emit([]);
    await tester.pump();
  });

  _widgetTest(
      'Q10 stale action callbacks cannot write during refresh or failure',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.feeds.single.emit(_rows());
    await tester.pump();
    final staleAction = tester.widget<IconButton>(_resolved).onPressed!;
    await tester.tap(_refresh);
    staleAction();
    await tester.pump();
    expect(h.writes, isEmpty);
    _expectActionsDisabled(tester);
    h.feeds.last.fail(Exception('read failure'));
    staleAction();
    await tester.pump();
    expect(h.writes, isEmpty);
    _expectActionsDisabled(tester);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    h.feeds.last.emit(_rows());
    await tester.pump();
    expect(tester.widget<IconButton>(_resolved).onPressed, isNotNull);
  });

  _widgetTest(
      'Q8 Q11 write completion during delayed refresh shares the replacement',
      (tester) async {
    final h = _Harness()..writeCompletion = Completer<void>();
    await h.mount(tester);
    final old = h.feeds.single;
    old.emit(_rows());
    await tester.pump();
    await tester.tap(_resolved);
    old.cancellation = Completer<void>();
    await tester.tap(_refresh);
    h.writeCompletion!.complete();
    scheduleMicrotask(() {
      old.emit(_rows('queued old event'));
      old.fail(Exception('queued old failure'));
      old.close();
    });
    await tester.pump();
    expect(h.factoryCalls, 1);
    expect(h.writes.length, 1);
    expect(find.text('User: patient-a'), findsOneWidget);
    expect(find.text('Error'), findsNothing);
    old.cancellation!.complete();
    await tester.pump();
    expect(h.factoryCalls, 2);
    h.feeds.last.emit(_rows('after write'));
    await tester.pump();
    expect(find.text('User: after write'), findsOneWidget);
    expect(h.writes, [('17', 'resolved')]);
  });

  group('R21 core regressions', () {
    for (final code in _jwtCodes) {
      _widgetTest('read $code clears rows and blocks retained actions',
          (tester) async {
        final error = _jwtError(code);
        final h = _Harness();
        await h.mount(tester);
        final feed = h.feeds.single;
        feed.emit(_rows());
        await tester.pump();
        final action = tester.widget<IconButton>(_resolved).onPressed!;
        feed.fail(error);
        await tester.pump();
        _expectNoIncidentRows();
        expect(
            find.text("Couldn't load the incident queue. $_jwtSessionReason"),
            findsOneWidget);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No incidents found.'), findsNothing);
        _expectNoPrivateDiagnostics();
        action();
        await tester.pump();
        expect(h.writes, isEmpty);
        expect(feed.cancels, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(h.factoryCalls, 1);
      });

      _widgetTest('mutation $code clears rows and blocks a second write',
          (tester) async {
        final error = _jwtError(code);
        final h = _Harness()..writeFailure = error;
        await h.mount(tester);
        final feed = h.feeds.single;
        feed.emit(_rows());
        await tester.pump();
        final action = tester.widget<IconButton>(_resolved).onPressed!;
        action();
        await tester.pump();
        _expectNoIncidentRows();
        expect(
            find.text(
                "Couldn't update the incident status. $_jwtSessionReason"),
            findsOneWidget);
        expect(
            find.text("Couldn't load the incident queue. $_jwtSessionReason"),
            findsOneWidget);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No incidents found.'), findsNothing);
        _expectNoPrivateDiagnostics();
        action();
        await tester.pump();
        expect(h.writes, [('17', 'resolved')]);
        expect(feed.cancels, 1);
        await tester.pump(const Duration(seconds: 20));
        expect(h.factoryCalls, 1);
      });
    }
  });

  group('R21 recovery', () {
    for (final mutation in [false, true]) {
      for (final empty in [false, true]) {
        _widgetTest(
            '${mutation ? 'mutation' : 'read'} denial recovers to ${empty ? 'empty' : 'rows'} only after fresh data',
            (tester) async {
          final error = _jwtError('PGRST303');
          final h = _Harness();
          if (mutation) h.writeFailure = error;
          await h.mount(tester);
          final old = h.feeds.single;
          old.emit(_rows());
          await tester.pump();
          final action = tester.widget<IconButton>(_resolved).onPressed!;
          if (mutation) {
            action();
          } else {
            old.fail(error);
          }
          await tester.pump();
          _expectNoIncidentRows();
          old.emit(_rows('late denied data'));
          old.fail(error);
          old.close();
          await tester.pump();
          _expectNoIncidentRows();
          expect(find.text('Error'), findsOneWidget);
          await tester.tap(find.text('Retry'));
          await tester.pump();
          expect(h.factoryCalls, 2);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('No incidents found.'), findsNothing);
          expect(find.textContaining('Previous data may be outdated'),
              findsNothing);
          action();
          await tester.pump();
          expect(h.writes, mutation ? [('17', 'resolved')] : isEmpty);
          h.feeds.last.emit(empty ? [] : _rows('recovered'));
          await tester.pump();
          expect(find.text('Error'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          if (empty) {
            expect(find.text('No incidents found.'), findsOneWidget);
          } else {
            expect(find.text('User: recovered'), findsOneWidget);
            expect(tester.widget<IconButton>(_resolved).onPressed, isNotNull);
          }
          old.emit(_rows('late old data'));
          old.fail(_jwtError('PGRST301'));
          old.close();
          await tester.pump();
          expect(find.text('Error'), findsNothing);
          expect(find.text('User: late old data'), findsNothing);
          expect(find.text(empty ? 'No incidents found.' : 'User: recovered'),
              findsOneWidget);
          expect(h.writes, mutation ? [('17', 'resolved')] : isEmpty);
          _expectNoPrivateDiagnostics();
        });
      }
    }

    _widgetTest('JWT denial waits for delayed cancellation before replacement',
        (tester) async {
      final h = _Harness();
      await h.mount(tester);
      final old = h.feeds.single;
      old.emit(_rows());
      await tester.pump();
      old.cancellation = Completer<void>();
      old.fail(_jwtError('PGRST301'));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(h.factoryCalls, 1);
      expect(old.cancels, 1);
      old.emit(_rows('late during cancellation'));
      old.fail(_jwtError('PGRST302'));
      old.close();
      await tester.pump(const Duration(seconds: 20));
      _expectNoIncidentRows();
      expect(h.factoryCalls, 1);
      expect(find.text('Error'), findsNothing);
      old.cancellation!.complete();
      await tester.pump();
      expect(h.factoryCalls, 2);
      expect(old.active, isFalse);
      h.feeds.last.emit(_rows('fresh after cancellation'));
      await tester.pump();
      old.fail(_jwtError('PGRST303'));
      await tester.pump();
      expect(find.text('User: fresh after cancellation'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
      expect(h.overlappingSubscriptions, 0);
      _expectNoPrivateDiagnostics();
    });

    _widgetTest('JWT-denied write after disposal is ignored', (tester) async {
      final h = _Harness()..writeCompletion = Completer<void>();
      await h.mount(tester);
      h.feeds.single.emit(_rows());
      await tester.pump();
      await tester.tap(_resolved);
      await tester.pumpWidget(const SizedBox.shrink());
      h.writeCompletion!.completeError(_jwtError('PGRST302'));
      await tester.pump(const Duration(seconds: 20));
      expect(h.writes, [('17', 'resolved')]);
      expect(h.factoryCalls, 1);
      expect(h.feeds.single.cancels, 1);
      expect(tester.takeException(), isNull);
    });

    _widgetTest('JWT refresh feedback keeps the refresh operation context',
        (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.feeds.single.emit(_rows());
      await tester.pump();
      await tester.tap(_refresh);
      await tester.pump();
      h.feeds.last.fail(_jwtError('PGRST303'));
      await tester.pump();
      _expectNoIncidentRows();
      expect(
          find.text("Couldn't refresh the incident queue. $_jwtSessionReason"),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      _expectNoPrivateDiagnostics();
    });
  });

  group('R21 original typed mutation denials', () {
    for (var index = 0; index < accessErrors.length; index++) {
      _widgetTest('legacy case $index still clears rows and blocks writes',
          (tester) async {
        final h = _Harness()..writeFailure = accessErrors[index];
        await h.mount(tester);
        h.feeds.single.emit(_rows());
        await tester.pump();
        final action = tester.widget<IconButton>(_resolved).onPressed!;
        action();
        await tester.pump();
        _expectNoIncidentRows();
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining("Couldn't update the incident status."),
            findsOneWidget);
        expect(find.textContaining("Couldn't load the incident queue."),
            findsOneWidget);
        expect(find.textContaining('token.secret'), findsNothing);
        expect(find.textContaining(_jwtSessionReason), findsNothing);
        action();
        await tester.pump();
        expect(h.writes, [('17', 'resolved')]);
        expect(h.feeds.single.cancels, 1);
      });
    }
  });

  group('R21 negative classification', () {
    final errors = <String, Object>{
      'PGRST300 server configuration': PostgrestException.fromJson({
        'code': 'PGRST300',
        'message': 'opaque-private-message',
        'details': 'opaque-private-details',
        'hint': 'opaque-private-hint',
      }, code: 500),
      'unknown PostgREST code': PostgrestException.fromJson({
        'code': 'PGRST399',
        'message': 'opaque-private-message',
        'details': 'opaque-private-details',
        'hint': 'opaque-private-hint',
      }, code: 500),
      'ordinary transient error': TimeoutException('opaque-private-message'),
      'untyped JWT marker': Exception('PGRST301 opaque-private-message'),
    };
    for (final entry in errors.entries) {
      _widgetTest('${entry.key} read retains outdated rows without writes',
          (tester) async {
        final h = _Harness();
        await h.mount(tester);
        h.feeds.single.emit(_rows());
        await tester.pump();
        final action = tester.widget<IconButton>(_resolved).onPressed!;
        h.feeds.single.fail(entry.value);
        await tester.pump();
        expect(find.text('User: patient-a'), findsOneWidget);
        expect(find.text('Previous incident data may be outdated.'),
            findsOneWidget);
        expect(find.text('Error'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.textContaining("Couldn't load the incident queue."),
            findsOneWidget);
        expect(find.textContaining(_jwtSessionReason), findsNothing);
        _expectActionsDisabled(tester);
        action();
        await tester.pump();
        expect(h.writes, isEmpty);
        _expectNoPrivateDiagnostics();
      });

      _widgetTest('${entry.key} mutation preserves rows and does not restart',
          (tester) async {
        final h = _Harness()..writeFailure = entry.value;
        await h.mount(tester);
        h.feeds.single.emit(_rows());
        await tester.pump();
        await tester.tap(_resolved);
        await tester.pump();
        expect(find.text('User: patient-a'), findsOneWidget);
        expect(find.textContaining("Couldn't update the incident status."),
            findsOneWidget);
        expect(find.textContaining(_jwtSessionReason), findsNothing);
        expect(find.text('Error'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(tester.widget<IconButton>(_resolved).onPressed, isNotNull);
        expect(h.feeds.single.cancels, 0);
        _expectNoPrivateDiagnostics();
        await tester.pump(const Duration(seconds: 20));
        expect(h.factoryCalls, 1);
        expect(h.writes, [('17', 'resolved')]);
      });
    }
  });
}
