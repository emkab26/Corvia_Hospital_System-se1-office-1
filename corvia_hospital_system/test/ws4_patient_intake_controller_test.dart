import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/controllers/patient_emergency_intake_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/ws4_http_fixture.dart';
import 'support/ws4_patient_intake_fixture.dart';

class MemoryOperationStore implements PatientEmergencyOperationStore {
  final values = <String, String>{};
  final writes = <String>[];
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read(String userId) async {
    if (failRead) throw StateError('private storage diagnostic');
    return values[userId];
  }

  @override
  Future<void> write(String userId, String operationId) async {
    if (failWrite) throw StateError('private storage diagnostic');
    writes.add(operationId);
    values[userId] = operationId;
  }

  @override
  Future<void> remove(String userId) async {
    values.remove(userId);
  }
}

class IntakeGateway implements PatientEmergencyIntakeGateway {
  String? actor = fixtureActor;
  final operations = <String>[];
  final inputs = <PatientEmergencyIntakeRequest>[];
  final lookups = <String>[];
  Future<PatientEmergencyIncident> Function(
      String, String, PatientEmergencyIntakeRequest)? onRequest;
  Future<PatientEmergencyIncident?> Function(String, String)? onLookup;
  @override
  String? get currentUserId => actor;
  @override
  Future<PatientEmergencyIncident> request(
      {required String userId,
      required String operationId,
      required PatientEmergencyIntakeRequest input}) {
    operations.add(operationId);
    inputs.add(input);
    return onRequest?.call(userId, operationId, input) ??
        Future.value(intakeIncident(
            operation: operationId, userId: userId, input: input));
  }

  @override
  Future<PatientEmergencyIncident> cancel(
          {required String userId,
          required String operationId,
          required String expectedVersion}) =>
      throw UnimplementedError(
          'Cancellation is covered by the cancellation tests.');

  @override
  Future<PatientEmergencyIncident?> lookup(
      {required String userId, required String operationId}) {
    lookups.add(operationId);
    return onLookup?.call(userId, operationId) ?? Future.value(null);
  }
}

PatientEmergencyIntakeController controller(
    IntakeGateway gateway, MemoryOperationStore store,
    {Duration timeout = const Duration(seconds: 15),
    Stream<String?>? changes}) {
  final value = PatientEmergencyIntakeController(
      gateway: gateway,
      operationStore: store,
      operationIdFactory: () => intakeOperation,
      timeout: timeout,
      userChanges: changes);
  addTearDown(value.dispose);
  return value;
}

void main() {
  test('operation generator uses UUID v4 and independent random identifiers',
      () {
    final ids = List.generate(100, (_) => createEmergencyOperationId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(id),
          isTrue);
    }
  });

  test('preferences store contains only the operation UUID per user', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesEmergencyOperationStore();
    await store.write(fixtureActor, intakeOperation);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(),
        {'corvia.ws4.emergency_operation.$fixtureActor'});
    expect(
        preferences.getString(preferences.getKeys().single), intakeOperation);
    expect(await store.read(fixtureActor), intakeOperation);
    expect(await store.read(nextIntakeOperation), isNull);
    await store.remove(fixtureActor);
    expect(preferences.getKeys(), isEmpty);
  });

  test('page startup performs no incident write and no allocation', () async {
    final gateway = IntakeGateway();
    final store = MemoryOperationStore();
    final state = controller(gateway, store);
    await state.initialize();
    expect(state.canSubmit, isTrue);
    expect(state.operationId, isNull);
    expect(gateway.operations, isEmpty);
    expect(store.writes, isEmpty);
  });

  test('explicit no-GPS submission persists identity before first request',
      () async {
    final gateway = IntakeGateway();
    final store = MemoryOperationStore();
    gateway.onRequest = (user, operation, input) async {
      expect(store.values[user], operation);
      expect(input.locationSource, 'unavailable');
      return intakeIncident(operation: operation, userId: user, input: input);
    };
    final state = controller(gateway, store);
    await state.initialize();
    await state.submit(PatientEmergencyIntakeRequest());
    expect(state.phase, PatientEmergencyIntakePhase.confirmed);
    expect(gateway.operations, [intakeOperation]);
    expect(store.writes, [intakeOperation]);
  });

  test('double tap is serialized while one request remains pending', () async {
    final pending = Completer<PatientEmergencyIncident>();
    final started = Completer<void>();
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) {
        started.complete();
        return pending.future;
      };
    final state = controller(gateway, MemoryOperationStore());
    await state.initialize();
    final input = PatientEmergencyIntakeRequest(address: 'Test entrance');
    final first = state.submit(input);
    await started.future;
    await state.submit(input);
    expect(gateway.operations, hasLength(1));
    expect(state.isBusy, isTrue);
    pending.complete(intakeIncident(input: input));
    await first;
    expect(state.incident!.address, 'Test entrance');
  });

  for (final failingRead in [true, false]) {
    test(
        '${failingRead ? 'read' : 'write'} persistence failure sends no incident',
        () async {
      final gateway = IntakeGateway();
      final store = MemoryOperationStore()
        ..failRead = failingRead
        ..failWrite = !failingRead;
      final state = controller(gateway, store);
      await state.initialize();
      if (!failingRead) await state.submit(PatientEmergencyIntakeRequest());
      expect(state.phase, PatientEmergencyIntakePhase.blocked);
      expect(gateway.operations, isEmpty);
      expect(state.errorMessage, isNot(contains('private')));
    });
  }

  test('lost response is reconciled before retry and does not create twice',
      () async {
    final input = PatientEmergencyIntakeRequest(details: 'Synthetic details');
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) async {
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
      };
    final store = MemoryOperationStore();
    final state = controller(gateway, store);
    await state.initialize();
    await state.submit(input);
    expect(state.phase, PatientEmergencyIntakePhase.unknown);
    expect(state.submittedRequest, same(input));
    gateway.onLookup = (_, operation) async =>
        intakeIncident(operation: operation, input: input);
    await state.retry();
    expect(state.phase, PatientEmergencyIntakePhase.confirmed);
    expect(gateway.operations, [intakeOperation]);
    expect(gateway.lookups, [intakeOperation]);
  });

  test('absent reconciliation retries same UUID and immutable payload',
      () async {
    final input =
        PatientEmergencyIntakeRequest(address: 'Original test entrance');
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) async =>
          throw const PatientEmergencyIntakeException(
              PatientEmergencyFailureKind.unknown);
    final store = MemoryOperationStore();
    final state = controller(gateway, store);
    await state.initialize();
    await state.submit(input);
    gateway.onRequest = (user, operation, original) async =>
        intakeIncident(operation: operation, userId: user, input: original);
    await state.retry();
    expect(gateway.operations, [intakeOperation, intakeOperation]);
    expect(gateway.inputs, [input, input]);
    expect(gateway.lookups, [intakeOperation]);
    expect(store.writes, [intakeOperation]);
  });

  test('reopening absent saved operation permits re-entry with the same UUID',
      () async {
    final gateway = IntakeGateway();
    final store = MemoryOperationStore()
      ..values[fixtureActor] = nextIntakeOperation;
    final state = controller(gateway, store);
    await state.initialize();
    expect(state.operationId, nextIntakeOperation);
    expect(state.canSubmit, isTrue);
    expect(gateway.operations, isEmpty);
    await state.submit(
        PatientEmergencyIntakeRequest(address: 'Re-entered test location'));
    expect(gateway.operations, [nextIntakeOperation]);
    expect(store.writes, isEmpty);
  });

  test('changed-payload rejection recovers the original authoritative request',
      () async {
    final original =
        PatientEmergencyIntakeRequest(address: 'Original test entrance');
    final gateway = IntakeGateway();
    final store = MemoryOperationStore()
      ..values[fixtureActor] = intakeOperation;
    final state = controller(gateway, store);
    await state.initialize();
    gateway.onRequest = (_, __, ___) async =>
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.invalidInput);
    gateway.onLookup = (_, operation) async =>
        intakeIncident(operation: operation, input: original);
    await state.submit(
        PatientEmergencyIntakeRequest(address: 'Different test entrance'));
    expect(state.phase, PatientEmergencyIntakePhase.confirmed);
    expect(state.incident!.address, original.address);
    expect(gateway.operations, [intakeOperation]);
    expect(store.values[fixtureActor], intakeOperation);
  });

  test(
      'definitive rejected input plus absent lookup allows correction using same UUID',
      () async {
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) async =>
          throw const PatientEmergencyIntakeException(
              PatientEmergencyFailureKind.invalidInput);
    final state = controller(gateway, MemoryOperationStore());
    await state.initialize();
    await state.submit(
        PatientEmergencyIntakeRequest(address: 'Rejected test details'));
    expect(state.phase, PatientEmergencyIntakePhase.ready);
    expect(state.submittedRequest, isNull);
    expect(state.operationId, intakeOperation);
    gateway.onRequest = null;
    await state.submit(
        PatientEmergencyIntakeRequest(address: 'Corrected test details'));
    expect(gateway.operations, [intakeOperation, intakeOperation]);
  });

  test('lookup failure leaves unknown outcome and prevents resend', () async {
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) async =>
          throw const PatientEmergencyIntakeException(
              PatientEmergencyFailureKind.unknown);
    final state = controller(gateway, MemoryOperationStore());
    await state.initialize();
    await state.submit(PatientEmergencyIntakeRequest());
    gateway.onLookup =
        (_, __) async => throw StateError('private network diagnostic');
    await state.retry();
    expect(state.phase, PatientEmergencyIntakePhase.unknown);
    expect(gateway.operations, hasLength(1));
    expect(state.errorMessage, isNot(contains('private')));
  });

  test(
      'timed-out write stays unknown and late result cannot overwrite reconciliation',
      () async {
    final pending = Completer<PatientEmergencyIncident>();
    final gateway = IntakeGateway()..onRequest = (_, __, ___) => pending.future;
    final state = controller(gateway, MemoryOperationStore(),
        timeout: const Duration(milliseconds: 1));
    await state.initialize();
    await state.submit(PatientEmergencyIntakeRequest());
    expect(state.phase, PatientEmergencyIntakePhase.unknown);
    gateway.onLookup = (_, __) async => intakeIncident(status: 'in_progress');
    await state.reconcile();
    pending.complete(intakeIncident(status: 'pending'));
    await Future<void>.delayed(Duration.zero);
    expect(state.incident!.status, 'in_progress');
    expect(gateway.operations, hasLength(1));
  });

  test(
      'only explicit action after terminal confirmation clears the old operation',
      () async {
    final gateway = IntakeGateway();
    final store = MemoryOperationStore()
      ..values[fixtureActor] = nextIntakeOperation;
    gateway.onLookup =
        (_, operation) async => intakeIncident(operation: operation);
    final state = controller(gateway, store);
    await state.initialize();
    await state.startNewRequest();
    expect(store.values[fixtureActor], nextIntakeOperation);
    expect(state.canStartNewRequest, isFalse);
    gateway.onLookup = (_, operation) async =>
        intakeIncident(operation: operation, status: 'resolved', version: '2');
    await state.reconcile();
    expect(state.canStartNewRequest, isTrue);
    expect(store.values[fixtureActor], nextIntakeOperation);
    await state.startNewRequest();
    expect(state.canSubmit, isTrue);
    expect(store.values[fixtureActor], isNull);
    expect(gateway.operations, isEmpty);
    await state.submit(PatientEmergencyIntakeRequest());
    expect(gateway.operations, [intakeOperation]);
  });

  test('session change clears sensitive state and ignores the old write result',
      () async {
    final pending = Completer<PatientEmergencyIncident>();
    final started = Completer<void>();
    final changes = StreamController<String?>.broadcast(sync: true);
    addTearDown(changes.close);
    final gateway = IntakeGateway()
      ..onRequest = (_, __, ___) {
        started.complete();
        return pending.future;
      };
    final store = MemoryOperationStore();
    final state = controller(gateway, store, changes: changes.stream);
    await state.initialize();
    final writing = state.submit(
        PatientEmergencyIntakeRequest(details: 'Synthetic private detail'));
    await started.future;
    gateway.actor = null;
    changes.add(null);
    expect(state.sessionEnded, isTrue);
    expect(state.submittedRequest, isNull);
    expect(state.incident, isNull);
    pending.complete(intakeIncident());
    await writing;
    expect(state.phase, PatientEmergencyIntakePhase.blocked);
    expect(state.incident, isNull);
    expect(store.values[fixtureActor], intakeOperation);
  });

  test('initial auth event for the same actor preserves startup lookup',
      () async {
    final changes = StreamController<String?>.broadcast(sync: true);
    addTearDown(changes.close);
    final lookup = Completer<PatientEmergencyIncident?>();
    final started = Completer<void>();
    final gateway = IntakeGateway()
      ..onLookup = (_, __) {
        started.complete();
        return lookup.future;
      };
    final store = MemoryOperationStore()
      ..values[fixtureActor] = intakeOperation;
    final state = controller(gateway, store, changes: changes.stream);
    final opening = state.initialize();
    await started.future;
    changes.add(fixtureActor);
    lookup.complete(intakeIncident());
    await opening;
    expect(state.phase, PatientEmergencyIntakePhase.confirmed);
    expect(gateway.lookups, hasLength(1));
    expect(gateway.operations, isEmpty);
  });

  test('dispose during pending lookup never emits or creates a request',
      () async {
    final lookup = Completer<PatientEmergencyIncident?>();
    final started = Completer<void>();
    final gateway = IntakeGateway()
      ..onLookup = (_, __) {
        started.complete();
        return lookup.future;
      };
    final store = MemoryOperationStore()
      ..values[fixtureActor] = intakeOperation;
    final state = PatientEmergencyIntakeController(
        gateway: gateway, operationStore: store);
    var notifications = 0;
    state.addListener(() => notifications++);
    final opening = state.initialize();
    await started.future;
    state.dispose();
    final before = notifications;
    lookup.complete(intakeIncident());
    await opening;
    expect(notifications, before);
    expect(gateway.operations, isEmpty);
  });
}
