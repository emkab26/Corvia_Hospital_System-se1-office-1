import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';

typedef IncidentStreamFactory = Stream<List<Map<String, dynamic>>> Function();
typedef IncidentStatusWriter = Future<void> Function(String id, String status);

class DispatchDashboard extends StatefulWidget {
  const DispatchDashboard({
    super.key,
    this.incidentStreamFactory,
    this.statusWriter,
  });

  final IncidentStreamFactory? incidentStreamFactory;
  final IncidentStatusWriter? statusWriter;

  @override
  State<DispatchDashboard> createState() => _DispatchDashboardState();
}

class _DispatchDashboardState extends State<DispatchDashboard> {
  // A UI loading bound only; this is not an incident/assignment deadline.
  static const _firstEventTimeout = Duration(seconds: 15);
  List<Map<String, dynamic>> incidents = [];
  bool _waiting = true;
  bool _hasSnapshot = false;
  bool _restartPending = false;
  bool _writing = false;
  bool _disposed = false;
  int _generation = 0;
  String? _readError;
  String? _writeError;
  String? _writeNotice;
  String _readAction = "Couldn't load the incident queue.";
  Timer? _firstEventTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Future<void>? _cancellation;

  bool get _canWrite =>
      !_disposed &&
      !_restartPending &&
      !_waiting &&
      _readError == null &&
      !_writing;

  bool _owns(int generation) => !_disposed && generation == _generation;

  bool _isJwtDenial(Object? error) =>
      error is PostgrestException &&
      const ['PGRST301', 'PGRST302', 'PGRST303'].contains(error.code);

  bool _isAccessDenial(Object? error) =>
      (error is AuthException &&
          (error.statusCode == '401' || error.statusCode == '403')) ||
      (error is PostgrestException &&
          const ['401', '403', '42501'].contains(error.code)) ||
      _isJwtDenial(error);

  String _queueErrorMessage(Object error, {required String whatFailed}) {
    if (_isJwtDenial(error)) {
      return '$whatFailed Your session could not be verified. '
          'Please sign in and try again.';
    }
    return friendlyErrorMessage(error, whatFailed: whatFailed);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restartFeed());
  }

  Future<void> _cancelFeed() {
    final pending = _cancellation;
    if (pending != null) return pending;
    final subscription = _subscription;
    if (subscription == null) return Future<void>.value();

    // Keep the handle on cancellation failure: Retry must finish cancellation
    // before creating a replacement, even if the stream throws synchronously.
    final cancellation = Future<void>.sync(subscription.cancel).then((_) {
      if (identical(_subscription, subscription)) _subscription = null;
    });
    _cancellation = cancellation.whenComplete(() => _cancellation = null);
    return _cancellation!;
  }

  Future<void> _restartFeed() async {
    if (_disposed || _restartPending) return;
    _restartPending = true;
    final generation = ++_generation; // Invalidate before cancellation.
    _firstEventTimer?.cancel();
    setState(() {
      _waiting = true;
      _readError = null;
      if (_hasSnapshot) _readAction = "Couldn't refresh the incident queue.";
    });

    try {
      await _cancelFeed();
      if (!_owns(generation)) return;
      final factory = widget.incidentStreamFactory ??
          () => Supabase.instance.client
              .from('incidents')
              .stream(primaryKey: ['id']).order('created_at', ascending: false);
      final stream = factory();
      _firstEventTimer = Timer(_firstEventTimeout, () {
        _failRead(generation,
            error: TimeoutException('First incident snapshot'));
      });
      _subscription = stream.listen(
        (data) {
          if (!_owns(generation)) return;
          _firstEventTimer?.cancel();
          setState(() {
            // Do not retain a mutable SDK/fake list as our cached snapshot.
            incidents =
                data.map((row) => Map<String, dynamic>.from(row)).toList();
            _hasSnapshot = true;
            _waiting = false;
            _readError = null;
          });
        },
        onError: (Object error) => _failRead(generation, error: error),
        onDone: () => _failRead(generation),
      );
      // Also handle a stream which delivers an error/done during listen itself.
      if (!_owns(generation)) await _cancelFeed();
    } catch (error) {
      _failRead(generation, error: error);
    } finally {
      _restartPending = false;
      if (!_disposed) setState(() {});
    }
  }

  void _failRead(int generation, {Object? error}) {
    if (!_owns(generation)) return;
    ++_generation; // End this generation; recovery requires explicit Retry.
    _firstEventTimer?.cancel();
    setState(() {
      _waiting = false;
      if (_isAccessDenial(error)) {
        incidents = [];
        _hasSnapshot = false;
      }
      _readError = error == null
          ? 'The incident queue stopped receiving updates. Please retry.'
          : _queueErrorMessage(error, whatFailed: _readAction);
    });
    // Cancellation errors are safe and leave the handle for the next Retry.
    // The generation is already invalid, so no callback can restore readiness.
    unawaited(_cancelFeed().catchError((Object _) {}));
  }

  Future<void> _updateStatus(String id, String status) async {
    if (!_canWrite || id.isEmpty) return;
    setState(() {
      _writing = true;
      _writeError = null;
      _writeNotice = null;
    });
    try {
      final writer = widget.statusWriter ??
          (String incidentId, String newStatus) async {
            await Supabase.instance.client.from('incidents').update({
              'status': newStatus,
            }).eq('id', incidentId);
          };
      await writer(id, status);
    } catch (error) {
      if (_disposed) return;
      setState(() {
        _writing = false;
        _writeError = _queueErrorMessage(
          error,
          whatFailed: "Couldn't update the incident status.",
        );
      });
      // Access denial applies to retained sensitive rows as well as reads.
      if (_isAccessDenial(error)) {
        _failRead(_generation, error: error);
      }
      return;
    }
    if (_disposed) return;
    setState(() {
      _writing = false;
      _writeNotice = 'Status update request completed.';
    });
    // Outside the write catch: a failed read must never be labelled a failed
    // write or automatically repeat a successful mutation.
    await _restartFeed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _firstEventTimer?.cancel();
    unawaited(_cancelFeed().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Dispatch Dashboard'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh incidents',
            onPressed: _restartPending ? null : _restartFeed,
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1D1E33), Color(0xFF111328)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            if (_writeError != null || _writeNotice != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _writeError ?? _writeNotice!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_waiting && _hasSnapshot)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Refreshing incident queue. Previous data may be outdated.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            if (_readError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Error', style: TextStyle(color: Colors.white)),
                    Text(_readError!,
                        style: const TextStyle(color: Colors.white)),
                    if (incidents.isNotEmpty)
                      const Text(
                        'Previous incident data may be outdated.',
                        style: TextStyle(color: Colors.white),
                      ),
                    TextButton(
                      onPressed: _restartPending ? null : _restartFeed,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _waiting && incidents.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : incidents.isEmpty
                      ? _readError != null
                          ? const SizedBox.shrink()
                          : Center(
                              child: Text(
                                'No incidents found.',
                                style: TextStyle(
                                  color: CorviaColors.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                            )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: ListView.builder(
                            itemCount: incidents.length,
                            itemBuilder: (context, index) {
                              final incident = incidents[index];

                              final id = incident['id']?.toString() ?? '';
                              final userId =
                                  incident['user_id']?.toString() ?? 'Unknown';
                              final latitude =
                                  incident['latitude']?.toString() ?? 'N/A';
                              final longitude =
                                  incident['longitude']?.toString() ?? 'N/A';
                              final status =
                                  incident['status']?.toString() ?? 'unknown';
                              final createdAt =
                                  incident['created_at']?.toString() ?? 'N/A';

                              return Card(
                                color: Colors.deepPurple.shade700,
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  title: Text(
                                    'User: $userId',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 5),
                                      Text(
                                        'Lat: $latitude, Lng: $longitude',
                                        style: TextStyle(
                                          color: CorviaColors.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        'Status: $status',
                                        style: const TextStyle(
                                          color: Colors.lightGreenAccent,
                                        ),
                                      ),
                                      Text(
                                        'Time: $createdAt',
                                        style: TextStyle(
                                          color: CorviaColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check,
                                          color: Colors.greenAccent,
                                        ),
                                        tooltip: 'Mark as Resolved',
                                        onPressed: id.isEmpty || !_canWrite
                                            ? null
                                            : () =>
                                                _updateStatus(id, 'resolved'),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.hourglass_top,
                                          color: Colors.orangeAccent,
                                        ),
                                        tooltip: 'Mark as In Progress',
                                        onPressed: id.isEmpty || !_canWrite
                                            ? null
                                            : () => _updateStatus(
                                                id, 'in_progress'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
