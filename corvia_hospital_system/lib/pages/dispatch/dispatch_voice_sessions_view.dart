
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/dispatch_voice_session_reader.dart';
import 'incoming_call_session_panel.dart';

/// Displays authorised call-session metadata.
///
/// The existing patient WebRTC controller is not reused
/// as an unverified dispatcher answer controller.
class DispatchVoiceSessionsView extends StatefulWidget {
  const DispatchVoiceSessionsView({
    super.key,
    this.gateway,
  });

  final DispatchVoiceSessionGateway? gateway;

  @override
  State<DispatchVoiceSessionsView> createState() =>
      _DispatchVoiceSessionsViewState();
}

class _DispatchVoiceSessionsViewState
    extends State<DispatchVoiceSessionsView> {
  late final DispatchVoiceSessionGateway _gateway;

  StreamSubscription<String?>? _auth;

  String? _actor;
  String? _error;

  List<IncomingCallSession> _sessions = const [];

  bool _loading = false;
  bool _denied = false;

  int _generation = 0;

  DateTime? _lastRead;

  @override
  void initState() {
    super.initState();

    _gateway = widget.gateway ??
        SupabaseDispatchVoiceSessionReader();

    _actor = _gateway.currentUserId;

    if (_actor == null) {
      _denied = true;
      _error =
          'Sign in with an authorised dispatch account.';
      return;
    }

    _auth = _gateway.userChanges.listen(
      (id) {
        if (id != _actor) {
          _deny();
        }
      },
      onError: (Object _) => _deny(),
    );

    unawaited(_load());
  }

  void _deny() {
    if (!mounted || _denied) return;

    _generation++;

    setState(() {
      _denied = true;
      _loading = false;
      _sessions = const [];
      _lastRead = null;

      _error =
          'Dispatch session changed. Reopen after signing in.';
    });
  }

  Future<void> _load() async {
    if (!mounted || _denied || _loading) {
      return;
    }

    if (_gateway.currentUserId != _actor) {
      _deny();
      return;
    }

    final generation = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
      _sessions = const [];
      _lastRead = null;
    });

    try {
      final sessions = await _gateway.load();

      if (!mounted ||
          _denied ||
          generation != _generation) {
        return;
      }

      if (_gateway.currentUserId != _actor) {
        _deny();
        return;
      }

      setState(() {
        _sessions = sessions;
        _lastRead = DateTime.now();
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          _denied ||
          generation != _generation) {
        return;
      }

      if (_gateway.currentUserId != _actor) {
        _deny();
        return;
      }

      setState(() {
        _sessions = const [];
        _lastRead = null;
        _loading = false;

        _error =
            'Voice sessions could not be verified. '
            'Check dispatch access, call_sessions RLS '
            'and connectivity.';
      });
    }
  }

  @override
  void dispose() {
    _generation++;

    unawaited(_auth?.cancel());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lastRead != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8,
            ),
            child: Text(
              'Session list received: '
              '${_lastRead!.toLocal()}',
            ),
          ),

        IncomingCallSessionPanel(
          sessions: _sessions,
          isLoading: _loading,
          errorMessage: _error,
          lastRefreshedAt: _lastRead,
          onRefresh: _denied ? null : _load,

          // Call action callbacks intentionally remain
          // disconnected until a verified dispatcher-side
          // call signalling service exists.
        ),
      ],
    );
  }
}
