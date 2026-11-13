import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/dispatch_terminal_history_service.dart';
import 'dispatch_history_report_panel.dart';
import 'dispatch_report_integrity.dart';

/// Read-only recent terminal history for the authenticated dispatch user.
/// Never claims to represent all hospital incidents or patient handovers.
class DispatchTerminalHistoryView extends StatefulWidget {
  const DispatchTerminalHistoryView({
    super.key,
    this.gateway,
  });

  final DispatchTerminalHistoryGateway? gateway;

  @override
  State<DispatchTerminalHistoryView> createState() =>
      _DispatchTerminalHistoryViewState();
}

class _DispatchTerminalHistoryViewState
    extends State<DispatchTerminalHistoryView> {
  late final DispatchTerminalHistoryGateway _gateway;
  StreamSubscription<String?>? _auth;
  String? _actor;
  String? _error;
  bool _loading = false;
  int _generation = 0;
  DispatchTerminalHistorySnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? SupabaseDispatchTerminalHistoryService();
    _actor = _gateway.currentUserId;
    if (_actor == null) {
      _error = 'Sign in with an authorised dispatch account.';
    } else {
      _auth = _gateway.userChanges.listen(
        (userId) {
          if (userId != _actor) _invalidate();
        },
        onError: (Object _) => _invalidate(),
      );
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _loading || _actor == null) return;
    if (_gateway.currentUserId != _actor) {
      _invalidate();
      return;
    }

    final token = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _snapshot = null;
    });
    try {
      final next = await _gateway.loadRecent();
      if (!mounted || token != _generation) return;
      if (_gateway.currentUserId != _actor) {
        _invalidate();
        return;
      }
      setState(() {
        _snapshot = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _generation) return;
      if (_gateway.currentUserId != _actor) {
        _invalidate();
        return;
      }
      setState(() {
        _loading = false;
        _snapshot = null;
        _error = 'Recent history could not be verified. '
            'Check your dispatch permissions, connectivity and RLS.';
      });
    }
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _actor = null;
      _loading = false;
      _snapshot = null;
      _error = 'Session changed. Reopen this screen after signing in.';
    });
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_auth?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final integrity = DispatchReportIntegrity.inspect(
      snapshot?.records ?? const <DispatchHistoryRecord>[],
      serverConfirmedComplete: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'Recent resolved / cancelled incidents',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Resolved means the incident was closed in the authorised '
          'event ledger. It does NOT prove hospital acceptance or '
          'completion of a patient handover.',
        ),
        if (snapshot?.hasMore == true)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('More terminal incidents exist outside this read window.'),
          ),
        if (integrity.hasIdentityProblems)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Invalid or duplicate incident IDs were excluded.'),
          ),
        DispatchHistoryReportPanel(
          records: integrity.safeRecords,
          scopeDescription: 'Recent RLS-authorised terminal incident '
              'records verified against corvia_incident_history',
          resultSetComplete: false,
          snapshotReceivedAt: snapshot?.receivedAt,
          isLoading: _loading,
          errorMessage: _error,
          onRefresh: _actor == null || _loading ? null : _refresh,
        ),
      ],
    );
  }
}
