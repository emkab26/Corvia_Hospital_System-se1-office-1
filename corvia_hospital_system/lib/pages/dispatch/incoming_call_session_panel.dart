
import 'package:flutter/material.dart';

/// Presentation state supplied by the existing, authorised call controller.
/// These permissions are server-derived, not inferred from a dashboard role.
enum IncomingCallState {
  ringing,
  connecting,
  active,
  ended,
  declined,
  unknown,
}

class IncomingCallSession {
  const IncomingCallSession({
    required this.id,
    required this.revision,
    required this.state,
    this.incidentId,
    this.displayName,
    this.lastUpdatedAt,
    this.ownedByMe = false,
    this.ownedByOther = false,
    this.canAnswer = false,
    this.canDecline = false,
    this.canHangUp = false,
  });

  final String id;
  final String revision;
  final IncomingCallState state;
  final String? incidentId;
  final String? displayName;
  final DateTime? lastUpdatedAt;
  final bool ownedByMe;
  final bool ownedByOther;
  final bool canAnswer;
  final bool canDecline;
  final bool canHangUp;

  bool get hasValidIdentity =>
      id.trim().isNotEmpty && revision.trim().isNotEmpty;
}

/// An adapter must use the existing signalling/session contract.
/// Authentication, ownership and revisions must be checked server-side.
/// The operation ID must be idempotent on the server.
typedef IncomingCallCommand = Future<void> Function({
  required String sessionId,
  required String expectedRevision,
  required String operationId,
});

enum _CallAction {
  answer,
  decline,
  hangUp,
}

class _PendingCommand {
  const _PendingCommand({
    required this.action,
    required this.sessionId,
    required this.expectedRevision,
    required this.operationId,
  });

  final _CallAction action;
  final String sessionId;
  final String expectedRevision;
  final String operationId;
}

/// UI-only panel. An absent controller callback disables that action.
/// A successful command does not prove that a media session is active.
class IncomingCallSessionPanel extends StatefulWidget {
  const IncomingCallSessionPanel({
    super.key,
    required this.sessions,
    this.isLoading = false,
    this.errorMessage,
    this.lastRefreshedAt,
    this.onRefresh,
    this.onAnswer,
    this.onDecline,
    this.onHangUp,
    this.newOperationId,
  });

  final List<IncomingCallSession> sessions;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastRefreshedAt;
  final Future<void> Function()? onRefresh;
  final IncomingCallCommand? onAnswer;
  final IncomingCallCommand? onDecline;
  final IncomingCallCommand? onHangUp;
  final String Function()? newOperationId;

  @override
  State<IncomingCallSessionPanel> createState() =>
      _IncomingCallSessionPanelState();
}

class _IncomingCallSessionPanelState
    extends State<IncomingCallSessionPanel> {
  _PendingCommand? _pending;

  bool _busy = false;
  bool _retryAllowed = false;

  String? _message;

  bool get _connected =>
      widget.newOperationId != null &&
      (widget.onAnswer != null ||
          widget.onDecline != null ||
          widget.onHangUp != null);

  IncomingCallCommand? _command(_CallAction action) {
    switch (action) {
      case _CallAction.answer:
        return widget.onAnswer;

      case _CallAction.decline:
        return widget.onDecline;

      case _CallAction.hangUp:
        return widget.onHangUp;
    }
  }

  String _actionLabel(_CallAction action) {
    switch (action) {
      case _CallAction.answer:
        return 'answer';

      case _CallAction.decline:
        return 'decline';

      case _CallAction.hangUp:
        return 'hang up';
    }
  }

  bool _allowed(
    IncomingCallSession session,
    _CallAction action,
  ) {
    if (_busy ||
        _pending != null ||
        widget.isLoading ||
        widget.errorMessage != null ||
        !session.hasValidIdentity ||
        session.ownedByOther ||
        widget.newOperationId == null ||
        _command(action) == null) {
      return false;
    }

    switch (action) {
      case _CallAction.answer:
        return session.state == IncomingCallState.ringing &&
            session.canAnswer;

      case _CallAction.decline:
        return session.state == IncomingCallState.ringing &&
            session.canDecline;

      case _CallAction.hangUp:
        return (session.state == IncomingCallState.active ||
                session.state == IncomingCallState.connecting) &&
            session.ownedByMe &&
            session.canHangUp;
    }
  }

  Future<bool> _confirm(_CallAction action) async {
    if (action == _CallAction.answer) {
      return true;
    }

    final label = action == _CallAction.decline
        ? 'Decline this voice call?'
        : 'End this voice call?';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: const Text(
          'This action affects the voice session only. '
          'It does not close or complete the emergency incident.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: const Text('Confirm call action'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _start(
    IncomingCallSession session,
    _CallAction action,
  ) async {
    if (!_allowed(session, action)) return;

    if (!await _confirm(action) || !mounted) {
      return;
    }

    if (!_allowed(session, action)) return;

    String operationId;

    try {
      operationId = widget.newOperationId!().trim();
    } catch (_) {
      operationId = '';
    }

    if (operationId.isEmpty) {
      setState(() {
        _message = 'Unable to create a call operation ID.';
      });
      return;
    }

    setState(() {
      _pending = _PendingCommand(
        action: action,
        sessionId: session.id,
        expectedRevision: session.revision,
        operationId: operationId,
      );

      _message = null;
      _retryAllowed = false;
    });

    await _sendPending();
  }

  Future<void> _sendPending() async {
    final pending = _pending;

    if (pending == null || _busy) return;

    final callback = _command(pending.action);

    if (callback == null) {
      setState(() {
        _message =
            'Call controller disconnected. Keep the pending action '
            'until its saved outcome can be verified.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await callback(
        sessionId: pending.sessionId,
        expectedRevision: pending.expectedRevision,
        operationId: pending.operationId,
      );

      if (!mounted) return;

      setState(() {
        _busy = false;
        _pending = null;
        _retryAllowed = false;

        _message =
            'Call command acknowledged by the controller. '
            'Check the refreshed session state for confirmation.';
      });

      await _refresh();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _retryAllowed = false;

        _message =
            'Outcome unknown. Refresh the saved call session '
            'before retrying this EXACT operation. A new call '
            'operation must not be created.';
      });
    }
  }

  Future<void> _refresh() async {
    final callback = widget.onRefresh;

    if (callback == null || _busy) return;

    try {
      await callback();

      if (mounted && _pending != null) {
        setState(() {
          _retryAllowed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Could not refresh call sessions. '
              'Existing state is unverified.';
        });
      }
    }
  }

  static String _stateLabel(IncomingCallState state) {
    switch (state) {
      case IncomingCallState.ringing:
        return 'Ringing';

      case IncomingCallState.connecting:
        return 'Connecting';

      case IncomingCallState.active:
        return 'Active call';

      case IncomingCallState.ended:
        return 'Ended';

      case IncomingCallState.declined:
        return 'Declined';

      case IncomingCallState.unknown:
        return 'Unverified';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('incoming-call-session-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.call_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Voice call sessions',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh saved call sessions',
                  onPressed: _busy || widget.onRefresh == null
                      ? null
                      : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            const Text(
              'Call ownership and action permissions must come '
              'from the authorised server session. Claiming an '
              'incident is NOT the same as answering a voice call.',
            ),

            if (!_connected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Voice controller is not connected. Answer, '
                  'decline and hang-up remain unavailable.',
                ),
              ),

            if (widget.isLoading || _busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),

            if (widget.errorMessage != null)
              Text(
                widget.errorMessage!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                ),
              ),

            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!),
              ),

            if (_pending != null) ...[
              const SizedBox(height: 8),

              Text(
                'Pending ${_actionLabel(_pending!.action)} '
                'for session ${_pending!.sessionId}.',
              ),

              OutlinedButton(
                onPressed: _busy ||
                        !_retryAllowed ||
                        _command(_pending!.action) == null
                    ? null
                    : _sendPending,
                child: Text(
                  'Retry same ${_actionLabel(_pending!.action)} '
                  'operation',
                ),
              ),
            ],

            if (!widget.isLoading && widget.sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No authorised voice sessions returned.',
                ),
              ),

            for (final session in widget.sessions) ...[
              const Divider(height: 24),

              Text(
                session.displayName?.trim().isNotEmpty == true
                    ? session.displayName!
                    : 'Voice session ${session.id}',
                style: theme.textTheme.titleSmall,
              ),

              const SizedBox(height: 4),

              Text(
                'Status: ${_stateLabel(session.state)}',
              ),

              Text(
                session.ownedByOther
                    ? 'Owned by another responder'
                    : session.ownedByMe
                        ? 'Owned by this responder'
                        : 'Responder ownership not confirmed',
              ),

              if (session.incidentId != null)
                Text(
                  'Linked incident: ${session.incidentId}',
                ),

              if (session.lastUpdatedAt != null)
                Text(
                  'Session updated: '
                  '${session.lastUpdatedAt!.toLocal()}',
                ),

              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed:
                        _allowed(session, _CallAction.answer)
                            ? () => _start(
                                  session,
                                  _CallAction.answer,
                                )
                            : null,
                    icon: const Icon(Icons.call),
                    label: const Text('Answer'),
                  ),

                  OutlinedButton.icon(
                    onPressed:
                        _allowed(session, _CallAction.decline)
                            ? () => _start(
                                  session,
                                  _CallAction.decline,
                                )
                            : null,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Decline'),
                  ),

                  OutlinedButton.icon(
                    onPressed:
                        _allowed(session, _CallAction.hangUp)
                            ? () => _start(
                                  session,
                                  _CallAction.hangUp,
                                )
                            : null,
                    icon: const Icon(
                      Icons.phone_disabled_outlined,
                    ),
                    label: const Text('Hang up'),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            Text(
              'Ending a voice call never completes the emergency '
              'case. The existing incident, clinical and handover '
              'workflows remain separate.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
