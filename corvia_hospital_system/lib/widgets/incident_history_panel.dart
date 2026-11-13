import 'dart:async';

import 'package:flutter/material.dart';

import '../services/incident_history_service.dart';

export '../models/dispatch/incident_history.dart';

typedef IncidentHistoryLoader = Future<IncidentHistory> Function(
    String incidentId);

/// Shows only recorded server events for one currently authorized incident.
class IncidentHistoryPanel extends StatefulWidget {
  const IncidentHistoryPanel({
    super.key,
    required this.incidentId,
    required this.revision,
    this.loader,
    this.service,
  }) : assert(loader == null || service == null);

  final String incidentId;
  final Object revision;
  final IncidentHistoryLoader? loader;
  final IncidentHistoryService? service;

  @override
  State<IncidentHistoryPanel> createState() => _IncidentHistoryPanelState();
}

class _IncidentHistoryPanelState extends State<IncidentHistoryPanel> {
  static const _readTimeout = Duration(seconds: 15);
  IncidentHistoryService? _service;
  StreamSubscription<String?>? _userSubscription;
  String? _actorUserId;
  IncidentHistory? _history;
  String? _error;
  bool _loading = false;
  bool _sessionChanged = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant IncidentHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        oldWidget.service != widget.service) {
      _generation++;
      unawaited(_userSubscription?.cancel());
      _userSubscription = null;
      _service = null;
      _actorUserId = null;
      _sessionChanged = false;
    }
    if (oldWidget.incidentId != widget.incidentId ||
        oldWidget.revision != widget.revision ||
        oldWidget.loader != widget.loader ||
        oldWidget.service != widget.service) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_userSubscription?.cancel());
    super.dispose();
  }

  bool _owns(int generation) => mounted && generation == _generation;

  void _invalidateSession() {
    if (!mounted || _sessionChanged) return;
    _generation++;
    setState(() {
      _sessionChanged = true;
      _history = null;
      _loading = false;
      _error = const IncidentHistoryException(
        IncidentHistoryFailureKind.authentication,
      ).message;
    });
  }

  IncidentHistoryService _getService() {
    if (_service == null) {
      final service = widget.service ?? IncidentHistoryService();
      _service = service;
      _actorUserId = service.currentUserId;
      _userSubscription = service.userChanges.listen((userId) {
        if (userId != _actorUserId) _invalidateSession();
      }, onError: (Object _) => _invalidateSession());
    }
    return _service!;
  }

  Future<void> _load() async {
    if (_sessionChanged) return;
    final generation = ++_generation;
    final incidentId = widget.incidentId;
    setState(() {
      _history = null;
      _error = null;
      _loading = true;
    });
    try {
      final loader = widget.loader;
      final service = loader == null ? _getService() : null;
      if (service != null &&
          (_actorUserId == null || service.currentUserId != _actorUserId)) {
        _invalidateSession();
        return;
      }
      final history =
          await (loader ?? service!.load)(incidentId).timeout(_readTimeout);
      if (!_owns(generation)) return;
      if (service != null && service.currentUserId != _actorUserId) {
        _invalidateSession();
        return;
      }
      if (history.incidentId != incidentId) {
        throw const IncidentHistoryException(
          IncidentHistoryFailureKind.invalidResponse,
        );
      }
      setState(() {
        _history = history;
        _loading = false;
      });
    } catch (error) {
      if (!_owns(generation)) return;
      if (_service != null && _service!.currentUserId != _actorUserId) {
        _invalidateSession();
        return;
      }
      setState(() {
        _history = null;
        _loading = false;
        _error = error is IncidentHistoryException
            ? error.message
            : const IncidentHistoryException(
                IncidentHistoryFailureKind.unavailable,
              ).message;
      });
    }
  }

  String _eventLabel(IncidentHistoryEvent event) => switch (event.eventType) {
        'created' => 'Request recorded',
        'claimed' => 'Accepted by Corvia dispatch',
        'cancelled' => 'Request cancelled',
        'resolved' => 'Request closed',
        'updated' => 'Corvia request updated',
        _ => 'Recorded status update',
      };

  @override
  Widget build(BuildContext context) {
    final events = _history?.events;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Request history',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Loading request history…'),
            ] else if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!))
            else if (events != null && events.isEmpty)
              const Text('No recorded history is available for this request.')
            else if (events != null)
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_eventLabel(event),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${event.recordedAt.toUtc().toIso8601String()} (UTC)',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _loading || _sessionChanged ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh history'),
            ),
          ],
        ),
      ),
    );
  }
}
