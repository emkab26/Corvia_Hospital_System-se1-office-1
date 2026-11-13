// dispatch_call_controller.dart
// Caller-side controller (fixed ringtone + speaker toggle placeholder)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../widgets/input_device_button.dart';
import 'windows_input_devices.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/env.dart';
import '../controllers/dispatch/call_countdown.dart';
import 'patient_incident_service.dart';

class Helper {
  static const MethodChannel _channel = MethodChannel('com.corvia.audio');

  static Future<void> setSpeakerphoneOn(bool on) async {
    try {
      await _channel.invokeMethod('setSpeakerphoneOn', {'on': on});
    } catch (e) {
      debugPrint('Speaker control unavailable.');
    }
  }
}

/// Manages the complex WebRTC state for emergency voice calls between a patient
/// and a dispatcher, including real-time signaling, redacted diagnostics, ringtone playback,
/// and channel subscriptions via Supabase Realtime.
class DispatchCallController {
  final SupabaseClient supabase;
  final BuildContext context;
  final VoidCallback onStateChanged;

  int? incidentId;

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String microphoneId = '';

  Future<void> selectMicrophone(String id) async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    final inputs = devices.where((d) => d.kind == 'audioinput').toList();
    if (inputs.isEmpty ||
        (id.isNotEmpty && !inputs.any((d) => d.deviceId == id))) {
      throw StateError('Microphone unavailable');
    }
    if (_localStream != null) {
      await rtc.Helper.selectAudioInput(
          id.isEmpty ? inputs.first.deviceId : id);
    }
    microphoneId = id;
    _notify();
  }

  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // Channels
  RealtimeChannel? _incidentChannel;
  RealtimeChannel? _callChannel;

  // Internal state
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCalling = false;
  bool _remoteConnected = false;
  String _statusMessage = 'Preparing emergency...';

  // Logging
  final List<String> _diagnostics = [];
  bool _disposed = false;
  bool _isCancelling = false;
  final Future<void> Function(int)? _cancelIncident;
  final Future<Position?> Function()? _lastPosition;
  final Future<Position> Function()? _currentPosition;

  // Ringtone
  final AudioPlayer _ringer = AudioPlayer();

  // Cancel timer & flag
  Timer? _cancelTimer;
  bool _canCancel = false;

  DispatchCallController({
    this.incidentId,
    required this.onStateChanged,
    required this.context,
    SupabaseClient? client,
    Future<void> Function(int)? cancelIncident,
    Future<Position?> Function()? lastPosition,
    Future<Position> Function()? currentPosition,
  })  : supabase = client ?? Supabase.instance.client,
        _cancelIncident = cancelIncident,
        _lastPosition = lastPosition,
        _currentPosition = currentPosition;

  late final CallCountdown _countdown = CallCountdown(
    onChanged: _notify,
    onElapsed: startVoiceCallAndSignal,
  );

  // Public getters
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCalling => _isCalling;
  bool get remoteConnected => _remoteConnected;
  String get statusMessage => _statusMessage;
  bool get logReady => _diagnostics.isNotEmpty;
  bool get canCancel => _canCancel;

  int get countdown => _countdown.remaining;
  bool get isCountingDown => _countdown.running;

  Widget get remoteRendererWidget => RTCVideoView(_remoteRenderer);
  Widget get ringingPulse =>
      const Icon(Icons.phone_in_talk, size: 72, color: Colors.orange);

  // Startup / Dispose
  Future<void> startup() async {
    await _initRenderer();
    if (_disposed) return;
    await _requestPermissions();
    if (_disposed) return;
    try {
      await _ringer.setVolume(1.0);
      _writeLog('Ringtone: volume set.');
    } catch (e) {
      _writeLog('Failed setting ringtone volume');
    }
    if (_disposed) return;
    await _createIncidentIfNeeded();
    _notify();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _countdown.dispose();
    unawaited(endCall());
    _cancelTimer?.cancel();
    try {
      _remoteRenderer.dispose();
    } catch (e) {
      _writeLog('Failed to dispose remote renderer');
    }
    _unsubscribeAll();
  }

  // Logging
  // Only static, redacted operation names are accepted at the call sites.
  // Memory-only: never write coordinates, identifiers, SDP, ICE or raw errors.
  void _writeLog(String operation) {
    if (_disposed) return;
    if (_diagnostics.length == 50) _diagnostics.removeAt(0);
    _diagnostics.add('${DateTime.now().toIso8601String()} $operation');
  }

  Future<String> _readLogs() async => _diagnostics.join('\n');

  void showLogs() async {
    final logs = await _readLogs();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Session Logs'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(logs,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs));
              Navigator.pop(context);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Logs copied')));
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  // Permissions & Incident
  Future<void> _requestPermissions() async {
    _writeLog('Requesting permissions...');
    try {
      await Permission.microphone.request();
      await Permission.location.request();
      _writeLog('Permissions: mic');
    } catch (e) {
      _writeLog('Permission error');
    }
  }

  Future<void> _createIncidentIfNeeded() async {
    if (_disposed || incidentId != null) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _statusMessage = 'Not logged in';
        _notify();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _writeLog('Position');
      if (_disposed) return;
      final res = await supabase
          .from('incidents')
          .insert({
            'user_id': user.id,
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'status': 'pending'
          })
          .select()
          .single();
      incidentId = res['id'];
      _statusMessage = 'Incident ready';
      _writeLog('Incident created');
      _notify();
    } catch (e) {
      _writeLog('Create incident failed');
      _statusMessage = 'Failed creating incident';
      _notify();
    }
  }

  // Renderer init
  Future<void> _initRenderer() async {
    try {
      await _remoteRenderer.initialize();
      _writeLog('Remote renderer initialized');
    } catch (e) {
      _writeLog('Renderer init error');
    }
  }

  // Call flow (caller)
  Future<void> startCallWithCountdown() async {
    if (_disposed || _isCalling) return;
    _countdown.start();
  }

  void cancelCountdown() => _countdown.cancel();

  Future<void> startVoiceCallAndSignal() async {
    if (_disposed || _isCalling) return;
    if (incidentId == null) {
      _statusMessage = 'No incident';
      _notify();
      return;
    }

    _isCalling = true;
    _statusMessage = 'Calling dispatch...';
    _notify();

    await _playRingtone(loop: true);
    await _subscribeIncidentChannel();

    try {
      final config = {'iceServers': Env.iceServers};
      _peerConnection = await createPeerConnection(config);

      _peerConnection?.onIceConnectionState = (state) => _writeLog('ICE state');
      _peerConnection?.onConnectionState = (state) => _writeLog('PC state');

      if (isWindowsDesktop &&
          microphoneId.isNotEmpty &&
          !(await WindowsInputDevices.callMicrophones())
              .any((d) => d.id == microphoneId)) {
        throw StateError(
            'Selected microphone disconnected. Choose another microphone.');
      }
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': isWindowsDesktop && microphoneId.isNotEmpty
            ? {
                'optional': [
                  {'sourceId': microphoneId}
                ]
              }
            : true,
        'video': false,
      });
      for (var track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onTrack = (RTCTrackEvent event) async {
        try {
          _writeLog('onTrack: streams');
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
            _remoteRenderer.srcObject = _remoteStream;
            _remoteConnected = true;
            _statusMessage = 'Connected to dispatch';
            _notify();
          } else {
            // fallback: attach track to a new MediaStream
            final ms = await createLocalMediaStream('remote-${event.track.id}');
            ms.addTrack(event.track);
            _remoteStream = ms;
            _remoteRenderer.srcObject = _remoteStream;
            _remoteConnected = true;
            _statusMessage = 'Connected to dispatch';
            _notify();
          }
        } catch (e) {
          _writeLog('onTrack error');
        }
      };

      _peerConnection!.onIceCandidate = (RTCIceCandidate? c) async {
        if (c == null || _callId == null) return;
        final candidatePayload = {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex
        };
        try {
          await supabase.from('call_ice_candidates').insert({
            'call_id': _callId,
            'sender': 'user',
            'candidate': candidatePayload
          });
          _writeLog('Sent ICE (user)');
        } catch (e) {
          _writeLog('Failed to send ICE');
        }
      };

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      final inserted = await supabase
          .from('call_sessions')
          .insert({
            'incident_id': incidentId,
            'user_id': supabase.auth.currentUser!.id,
            'offer_sdp': offer.sdp,
            'status': 'ringing'
          })
          .select()
          .single();
      _callId = inserted['id'];
      _writeLog('Call session created id');

      await _joinCallChannel(_callId!);

      // Start the 15-second cancel window
      startCancelTimer();
    } catch (e) {
      _writeLog('Call error');
    }
  }

  void startCancelTimer() {
    if (_disposed) return;
    _canCancel = true;
    _cancelTimer?.cancel();
    _cancelTimer = Timer(const Duration(seconds: 15), () {
      if (context.mounted) {
        _canCancel = false;
        _writeLog('Cancel window expired');
        _notify();
      }
    });
    _notify();
  }

  // Cancel the dispatch after PIN verification.
  Future<bool> cancelDispatch(String enteredPin) async {
    if (_disposed ||
        _isCancelling ||
        !_canCancel ||
        incidentId == null ||
        enteredPin != Env.emergencyCancelPin) {
      return false;
    }
    _isCancelling = true;
    try {
      final cancel = _cancelIncident ??
          PatientIncidentService(supabase).cancelUnclaimedIncident;
      await cancel(incidentId!);
      if (_disposed) return false;
      await endCall();
      _canCancel = false;
      _cancelTimer?.cancel();
      _statusMessage = 'Dispatch cancelled';
      _notify();
      return true;
    } catch (_) {
      _statusMessage = 'Cancellation could not be confirmed. Contact dispatch.';
      _notify();
      return false;
    } finally {
      _isCancelling = false;
    }
  }

  int? _callId;

  Future<void> _subscribeIncidentChannel() async {
    if (incidentId == null) return;
    _incidentChannel = supabase.channel('incident_$incidentId');

    _incidentChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_sessions',
      filter: PostgresChangeFilter(
          column: 'incident_id',
          type: PostgresChangeFilterType.eq,
          value: '$incidentId'),
      callback: (payload) {
        _writeLog('Call session inserted (incident channel)');
      },
    );

    try {
      _incidentChannel!.subscribe();
      _writeLog('Subscribed to incident channel');
    } catch (e) {
      _writeLog('Incident subscribe failed');
    }
  }

  Future<void> _joinCallChannel(int callId) async {
    _writeLog('Joining call_');
    _callChannel = supabase.channel('call_$callId');

    _callChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_ice_candidates',
      filter: PostgresChangeFilter(
          column: 'call_id',
          type: PostgresChangeFilterType.eq,
          value: '$callId'),
      callback: (payload) async {
        final row = payload.newRecord;
        try {
          _writeLog('ICE row received');
          final sender = (row['sender'] ?? '').toString();
          if (sender == 'dispatch') {
            dynamic c = row['candidate'];
            if (c is String) {
              try {
                c = jsonDecode(c);
              } catch (e) {
                _writeLog('Failed to parse ICE candidate JSON');
              }
            }
            final mline = c['sdpMLineIndex'];
            int? idx;
            if (mline is int) {
              idx = mline;
            } else if (mline is String) {
              idx = int.tryParse(mline);
            }
            final ice = RTCIceCandidate(c['candidate'], c['sdpMid'], idx);
            await _peerConnection?.addCandidate(ice);
            _writeLog('Added ICE from dispatch');
          } else {
            _writeLog('Ignored ICE sender');
          }
        } catch (e) {
          _writeLog('Failed to handle ICE row');
        }
      },
    );

    _callChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'call_sessions',
      filter: PostgresChangeFilter(
          column: 'id', type: PostgresChangeFilterType.eq, value: '$callId'),
      callback: (payload) async {
        final row = payload.newRecord;
        try {
          _writeLog('Call session updated');
          if (row['status'] == 'answered' && row['answer_sdp'] != null) {
            await _stopRingtone();
            final answer = RTCSessionDescription(row['answer_sdp'], 'answer');
            await _peerConnection?.setRemoteDescription(answer);
            _statusMessage = 'Connected to dispatch';

            try {
              await Helper.setSpeakerphoneOn(false);
              _writeLog('Requested speakerphone off (native).');
            } catch (e) {
              _writeLog('Speakerphone toggle request failed');
            }

            _notify();
            _writeLog('Answer applied');
          }
        } catch (e) {
          _writeLog('Answer handling error');
        }
      },
    );

    try {
      _callChannel!.subscribe();
      _writeLog('Subscribed to call channel');
    } catch (e) {
      _writeLog('Call channel subscribe failed');
    }
  }

  // End call + cleanup
  Future<void> endCall() async {
    _countdown.cancel();
    await _stopRingtone();
    _cancelTimer?.cancel();
    _canCancel = false;
    try {
      await _peerConnection?.close();
    } catch (e) {
      _writeLog('Failed to close peer connection');
    }
    try {
      await _localStream?.dispose();
    } catch (e) {
      _writeLog('Failed to dispose local stream');
    }
    if (_callId != null) {
      try {
        await supabase
            .from('call_sessions')
            .update({'status': 'ended'}).eq('id', _callId!);
      } catch (e) {
        _writeLog('Update ended failed');
      }
    }
    _unsubscribeAll();
    _callId = null;
    _isCalling = false;
    _remoteConnected = false;
    _statusMessage = 'Call ended';
    _notify();
  }

  void _unsubscribeAll() {
    try {
      _incidentChannel?.unsubscribe();
    } catch (e) {
      _writeLog('Failed to unsubscribe incident channel');
    }
    try {
      _callChannel?.unsubscribe();
    } catch (e) {
      _writeLog('Failed to unsubscribe call channel');
    }
  }

  Future<Position?> getLastKnownOrFetchLocation() async {
    try {
      final last =
          await (_lastPosition?.call() ?? Geolocator.getLastKnownPosition());
      if (last != null && _validPosition(last)) return last;
    } catch (_) {
      // Some platforms do not support last-known location; still try a fresh fix.
    }
    try {
      final position = await (_currentPosition?.call() ??
          Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.best),
          ));
      return _validPosition(position) ? position : null;
    } catch (_) {
      return null;
    }
  }

  bool _validPosition(Position p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0;

  // Controls
  void toggleMute() {
    if (_localStream == null) return;
    final track = _localStream!.getAudioTracks().first;
    track.enabled = !track.enabled;
    _isMuted = !track.enabled;
    _writeLog('Mute toggled');
    _notify();
  }

  void toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      _writeLog('Speaker toggled');
    } catch (e) {
      _writeLog('Speaker toggle error');
    }
    _notify();
  }

  Future<void> _playRingtone({bool loop = false}) async {
    try {
      await _ringer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _ringer.play(AssetSource('ringing.mp3'), volume: 1.0);
      _writeLog('Ringtone started');
    } catch (e) {
      _writeLog('Ringtone error');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringer.stop();
      _writeLog('Ringtone stopped');
    } catch (e) {
      _writeLog('Ringtone stop error');
    }
  }

  void _notify() {
    if (!_disposed) onStateChanged();
  }
}
