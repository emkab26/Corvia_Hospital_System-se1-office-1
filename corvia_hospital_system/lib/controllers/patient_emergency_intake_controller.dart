import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/patient_emergency_intake_service.dart';
export '../services/patient_emergency_intake_service.dart';

enum PatientEmergencyIntakePhase {
  initializing,
  ready,
  submitting,
  cancelling,
  reconciling,
  unknown,
  confirmed,
  blocked
}

abstract interface class PatientEmergencyOperationStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String operationId);
  Future<void> remove(String userId);
}

/// Stores only one opaque operation UUID per authenticated user. Never stores
/// coordinates, address, health details or the incident response.
class SharedPreferencesEmergencyOperationStore
    implements PatientEmergencyOperationStore {
  String _key(String userId) => 'corvia.ws4.emergency_operation.$userId';
  @override
  Future<String?> read(String userId) async =>
      (await SharedPreferences.getInstance()).getString(_key(userId));
  @override
  Future<void> write(String userId, String operationId) async {
    if (!isEmergencyUuid(userId) || !isEmergencyUuid(operationId)) {
      throw StateError('Invalid operation identity.');
    }
    if (!await (await SharedPreferences.getInstance())
        .setString(_key(userId), operationId)) {
      throw StateError('Operation persistence failed.');
    }
  }

  @override
  Future<void> remove(String userId) async {
    if (!await (await SharedPreferences.getInstance()).remove(_key(userId))) {
      throw StateError('Operation persistence failed.');
    }
  }
}

String createEmergencyOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Owns only patient intake. initialize()/reconcile() are lookup-only; neither
/// location acquisition nor page construction creates an emergency incident.
class PatientEmergencyIntakeController extends ChangeNotifier {
  PatientEmergencyIntakeController(
      {PatientEmergencyIntakeGateway? gateway,
      PatientEmergencyOperationStore? operationStore,
      Stream<String?>? userChanges,
      Duration timeout = const Duration(seconds: 15),
      String Function()? operationIdFactory})
      : _gateway = gateway ?? PatientEmergencyIntakeService(),
        _store = operationStore ?? SharedPreferencesEmergencyOperationStore(),
        _timeout = timeout,
        _operationIdFactory = operationIdFactory ?? createEmergencyOperationId {
    final changes = userChanges ??
        (_gateway is PatientEmergencyIntakeService
            ? (_gateway as PatientEmergencyIntakeService).userChanges
            : null);
    _subscription = changes?.listen((userId) {
      if (_disposed || userId == _userId) return;
      _resetSession(userId);
      if (userId != null) unawaited(initialize());
    });
  }
  final PatientEmergencyIntakeGateway _gateway;
  final PatientEmergencyOperationStore _store;
  final Duration _timeout;
  final String Function() _operationIdFactory;
  StreamSubscription<String?>? _subscription;
  bool _disposed = false;
  int _generation = 0;
  String? _userId;
  String? _operationId;
  PatientEmergencyIntakeRequest? _submittedRequest;
  PatientEmergencyIncident? _incident;
  String? _errorMessage;
  bool _cancellationUnconfirmed = false;
  PatientEmergencyIntakePhase _phase = PatientEmergencyIntakePhase.initializing;

  PatientEmergencyIntakePhase get phase => _phase;
  String? get activeUserId => _userId;
  bool get sessionEnded => _userId == null || _userId != _gateway.currentUserId;
  String? get operationId => _operationId;
  PatientEmergencyIntakeRequest? get submittedRequest => _submittedRequest;
  PatientEmergencyIncident? get incident => _incident;
  String? get errorMessage => _errorMessage;
  bool get cancellationUnconfirmed => _cancellationUnconfirmed;
  bool get isBusy => const {
        PatientEmergencyIntakePhase.initializing,
        PatientEmergencyIntakePhase.submitting,
        PatientEmergencyIntakePhase.cancelling,
        PatientEmergencyIntakePhase.reconciling
      }.contains(_phase);
  bool get canSubmit =>
      !_disposed &&
      !sessionEnded &&
      _phase == PatientEmergencyIntakePhase.ready;
  bool get canStartNewRequest =>
      !_disposed &&
      !sessionEnded &&
      _phase == PatientEmergencyIntakePhase.confirmed &&
      _incident?.isTerminal == true;
  bool get canCancel =>
      !_disposed &&
      !sessionEnded &&
      _phase == PatientEmergencyIntakePhase.confirmed &&
      _incident?.status == 'pending';

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _resetSession(String? userId) {
    _generation++;
    _userId = userId;
    _operationId = null;
    _submittedRequest = null;
    _incident = null;
    _cancellationUnconfirmed = false;
    _phase = PatientEmergencyIntakePhase.blocked;
    _errorMessage = const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.authentication)
        .message;
    _emit();
  }

  bool _owns(int generation, String userId) {
    if (_disposed || generation != _generation) return false;
    if (_gateway.currentUserId != userId) {
      _resetSession(_gateway.currentUserId);
      return false;
    }
    return _userId == userId;
  }

  bool _sameSession() {
    if (_disposed) return false;
    if (_userId == null || _gateway.currentUserId != _userId) {
      _resetSession(_gateway.currentUserId);
      return false;
    }
    return true;
  }

  void _failure(Object error, {bool unsent = false}) {
    final safe = error is PatientEmergencyIntakeException
        ? error
        : const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
    _errorMessage = _cancellationUnconfirmed &&
            safe.kind != PatientEmergencyFailureKind.authentication &&
            safe.kind != PatientEmergencyFailureKind.configuration
        ? 'Cancellation could not be confirmed. The request may still be active. Check its status before trying to cancel again.'
        : safe.message;
    if (safe.kind == PatientEmergencyFailureKind.authentication ||
        safe.kind == PatientEmergencyFailureKind.configuration) {
      _incident = null;
      _submittedRequest = null;
      _phase = PatientEmergencyIntakePhase.blocked;
    } else {
      _phase = unsent
          ? PatientEmergencyIntakePhase.ready
          : PatientEmergencyIntakePhase.unknown;
    }
    _emit();
  }

  void _confirm(
      PatientEmergencyIncident result, String userId, String operationId) {
    final previous = _incident;
    if (result.userId != userId ||
        result.operationId != operationId ||
        (previous != null &&
            (result.incidentId != previous.incidentId ||
                result.request != previous.request ||
                result.createdAt != previous.createdAt ||
                BigInt.parse(result.version) < BigInt.parse(previous.version) ||
                (result.version == previous.version &&
                    result.status != previous.status)))) {
      throw const PatientEmergencyIntakeException(
          PatientEmergencyFailureKind.unknown);
    }
    _incident = result;
    _submittedRequest = result.request;
    _cancellationUnconfirmed = false;
    _phase = PatientEmergencyIntakePhase.confirmed;
    _errorMessage = null;
    _emit();
  }

  Future<void> initialize() async {
    if (_disposed) return;
    final userId = _gateway.currentUserId;
    if (!isEmergencyUuid(userId)) {
      _resetSession(null);
      return;
    }
    final generation = ++_generation;
    _userId = userId;
    _incident = null;
    _submittedRequest = null;
    _operationId = null;
    _cancellationUnconfirmed = false;
    _phase = PatientEmergencyIntakePhase.initializing;
    _errorMessage = null;
    _emit();
    try {
      final operation = await _store.read(userId!).timeout(_timeout);
      if (!_owns(generation, userId)) return;
      if (operation != null && !isEmergencyUuid(operation)) {
        _phase = PatientEmergencyIntakePhase.blocked;
        _errorMessage =
            'The saved request reference could not be read. Call directly for help.';
        _emit();
        return;
      }
      _operationId = operation;
      if (operation != null) {
        await _lookup(generation, userId, operation);
      } else {
        _phase = PatientEmergencyIntakePhase.ready;
        _emit();
      }
    } catch (_) {
      if (!_owns(generation, userId!)) return;
      // A failed local read must never create a second operation UUID.
      _phase = PatientEmergencyIntakePhase.blocked;
      _errorMessage =
          'The saved request reference could not be read. Retry opening this page or call directly.';
      _emit();
    }
  }

  Future<bool> _lookup(int generation, String userId, String operationId,
      {bool rejectedInput = false}) async {
    _phase = PatientEmergencyIntakePhase.reconciling;
    _errorMessage = null;
    _emit();
    try {
      final result = await _gateway
          .lookup(userId: userId, operationId: operationId)
          .timeout(_timeout);
      if (!_owns(generation, userId)) return false;
      if (result != null) {
        _confirm(result, userId, operationId);
        return false;
      }
      // Absence cannot undo a previously confirmed incident or establish that a
      // cancellation succeeded. Keep the snapshot until a valid status arrives.
      if (_incident != null || _cancellationUnconfirmed) {
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
      }
      _incident = null;
      // A definitive invalid-input rejection plus absent lookup permits corrected
      // input with the same operation UUID. Never allocate a replacement UUID.
      if (rejectedInput) _submittedRequest = null;
      _phase = PatientEmergencyIntakePhase.ready;
      _errorMessage = rejectedInput
          ? const PatientEmergencyIntakeException(
                  PatientEmergencyFailureKind.invalidInput)
              .message
          : null;
      _emit();
      return true;
    } catch (error) {
      if (_owns(generation, userId)) _failure(error);
      return false;
    }
  }

  Future<void> reconcile() async {
    if (!_sameSession() || isBusy) return;
    final operation = _operationId;
    if (operation == null) {
      await initialize();
      return;
    }
    await _lookup(++_generation, _userId!, operation);
  }

  /// Cancellation is always explicit. An uncertain attempt must be reconciled
  /// before another attempt; no timeout or lookup automatically cancels again.
  Future<void> cancel() async {
    if (!_sameSession() || !canCancel) return;
    final snapshot = _incident!;
    final userId = _userId!;
    final operation = _operationId!;
    final generation = ++_generation;
    _cancellationUnconfirmed = true;
    _phase = PatientEmergencyIntakePhase.cancelling;
    _errorMessage = null;
    _emit();
    if (!_owns(generation, userId)) return;
    try {
      final result = await _gateway
          .cancel(
              userId: userId,
              operationId: operation,
              expectedVersion: snapshot.version)
          .timeout(_timeout);
      if (!_owns(generation, userId)) return;
      if (result.status != 'cancelled' ||
          BigInt.parse(result.version) !=
              BigInt.parse(snapshot.version) + BigInt.one) {
        throw const PatientEmergencyIntakeException(
            PatientEmergencyFailureKind.unknown);
      }
      _confirm(result, userId, operation);
    } catch (error) {
      if (!_owns(generation, userId)) return;
      if (error is PatientEmergencyIntakeException &&
          const {
            PatientEmergencyFailureKind.conflict,
            PatientEmergencyFailureKind.invalidInput
          }.contains(error.kind)) {
        await _lookup(generation, userId, operation);
        if (_owns(generation, userId) &&
            _phase == PatientEmergencyIntakePhase.confirmed &&
            _incident?.status != 'cancelled') {
          _errorMessage =
              'The request was not cancelled. Its latest status is shown below.';
          _emit();
        }
      } else {
        _failure(error);
      }
    }
  }

  Future<void> submit(PatientEmergencyIntakeRequest input) async {
    if (!_sameSession() || !canSubmit) return;
    if (_submittedRequest != null && _submittedRequest != input) {
      _errorMessage =
          'Retry the original request or check its status before changing details.';
      _emit();
      return;
    }
    final userId = _userId!;
    final generation = ++_generation;
    _phase = PatientEmergencyIntakePhase.submitting;
    _errorMessage = null;
    _emit();
    if (_operationId == null) {
      try {
        final operation = _operationIdFactory();
        if (!isEmergencyUuid(operation)) {
          throw StateError('Invalid operation identity.');
        }
        await _store.write(userId, operation).timeout(_timeout);
        if (!_owns(generation, userId)) return;
        _operationId = operation;
      } catch (_) {
        if (!_owns(generation, userId)) return;
        // Persistence can fail after writing; force a fresh read before another UUID.
        _phase = PatientEmergencyIntakePhase.blocked;
        _errorMessage =
            'The request reference could not be saved. No request was sent. Reopen this page or call directly.';
        _emit();
        return;
      }
    }
    await _send(generation, userId, _operationId!, input);
  }

  Future<void> _send(int generation, String userId, String operationId,
      PatientEmergencyIntakeRequest input) async {
    if (!_owns(generation, userId)) return;
    _submittedRequest = input;
    _phase = PatientEmergencyIntakePhase.submitting;
    _errorMessage = null;
    _emit();
    try {
      final result = await _gateway
          .request(userId: userId, operationId: operationId, input: input)
          .timeout(_timeout);
      if (_owns(generation, userId)) _confirm(result, userId, operationId);
    } catch (error) {
      if (!_owns(generation, userId)) return;
      if (error is PatientEmergencyIntakeException &&
          error.kind == PatientEmergencyFailureKind.invalidInput) {
        await _lookup(generation, userId, operationId, rejectedInput: true);
      } else {
        _failure(error);
      }
    }
  }

  /// Reconcile before retrying; after reopening, absent input requires re-entry.
  Future<void> retry() async {
    if (!_sameSession() || isBusy || _incident != null) return;
    final operation = _operationId;
    if (operation == null) {
      await initialize();
      return;
    }
    final userId = _userId!;
    final generation = ++_generation;
    if (await _lookup(generation, userId, operation) &&
        _owns(generation, userId)) {
      final input = _submittedRequest;
      if (input != null) await _send(generation, userId, operation, input);
    }
  }

  Future<void> startNewRequest() async {
    if (!_sameSession() || !canStartNewRequest) return;
    final userId = _userId!;
    final generation = ++_generation;
    _phase = PatientEmergencyIntakePhase.initializing;
    _emit();
    try {
      await _store.remove(userId).timeout(_timeout);
      if (!_owns(generation, userId)) return;
      _operationId = null;
      _submittedRequest = null;
      _incident = null;
      _cancellationUnconfirmed = false;
      _errorMessage = null;
      _phase = PatientEmergencyIntakePhase.ready;
      _emit();
    } catch (_) {
      if (!_owns(generation, userId)) return;
      _phase = PatientEmergencyIntakePhase.confirmed;
      _errorMessage =
          'The previous request reference could not be cleared. Try again before starting another request.';
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    _incident = null;
    _submittedRequest = null;
    super.dispose();
  }
}
