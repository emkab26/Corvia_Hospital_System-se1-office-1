import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Mock call service to simulate Supabase interactions during dispatch flow
class MockCallService {
  int _nextCallId = 5001;
  int _nextIncidentId = 1201;

  final Map<int, Map<String, dynamic>> _callSessions = {};
  final Map<int, List<Map<String, dynamic>>> _iceCandidates = {};

  int createIncident() {
    return _nextIncidentId++;
  }

  int createCallSession({
    required int incidentId,
    required String offerSdp,
  }) {
    final callId = _nextCallId++;
    _callSessions[callId] = {
      'id': callId,
      'incident_id': incidentId,
      'status': 'ringing',
      'offer_sdp': offerSdp,
      'answer_sdp': null,
    };
    _iceCandidates[callId] = [];
    return callId;
  }

  void addIceCandidate({
    required int callId,
    required String sender,
    required Map<String, dynamic> candidate,
  }) {
    if (_iceCandidates.containsKey(callId)) {
      _iceCandidates[callId]!.add({
        'call_id': callId,
        'sender': sender,
        'candidate': candidate,
      });
    }
  }

  void answerCall({
    required int callId,
    required String answerSdp,
  }) {
    if (_callSessions.containsKey(callId)) {
      _callSessions[callId]!['status'] = 'answered';
      _callSessions[callId]!['answer_sdp'] = answerSdp;
    }
  }

  void endCall({required int callId}) {
    if (_callSessions.containsKey(callId)) {
      _callSessions[callId]!['status'] = 'ended';
    }
  }

  Map<String, dynamic>? getCallSession(int callId) {
    return _callSessions[callId];
  }

  List<Map<String, dynamic>> getIceCandidates(int callId) {
    return _iceCandidates[callId] ?? [];
  }
}

/// Complete mock controller that doesn't extend the real DispatchCallController
class MockDispatchController {
  final MockCallService mockService;
  VoidCallback onStateChanged;
  final BuildContext context;

  int? incidentId;
  int? _callId;
  bool _isCalling = false;
  bool _remoteConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String _statusMessage = 'Preparing emergency...';

  MockDispatchController({
    this.incidentId,
    required this.onStateChanged,
    required this.context,
    required this.mockService,
  });

  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCalling => _isCalling;
  bool get remoteConnected => _remoteConnected;
  String get statusMessage => _statusMessage;
  Widget get remoteRendererWidget => const SizedBox.shrink();
  Widget get ringingPulse => const Icon(Icons.phone_in_talk, size: 72, color: Colors.orange);

  Future<void> startup() async {
    // Simulate incident creation during startup
    incidentId = mockService.createIncident();
    _statusMessage = 'Incident ready';
    onStateChanged();
  }

  Future<void> startVoiceCallAndSignal() async {
    _isCalling = true;
    _statusMessage = 'Calling dispatch...';
    onStateChanged();

    if (incidentId != null) {
      _callId = mockService.createCallSession(
        incidentId: incidentId!,
        offerSdp: 'mock-offer-sdp-v1',
      );
    }

    if (_callId != null) {
      mockService.addIceCandidate(
        callId: _callId!,
        sender: 'user',
        candidate: {
          'candidate': 'candidate:123 1 udp 123 127.0.0.1 5000 typ host',
          'sdpMid': 'audio',
          'sdpMLineIndex': 0,
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 1));

      mockService.answerCall(
        callId: _callId!,
        answerSdp: 'mock-answer-sdp-v1',
      );
      _remoteConnected = true;
      _statusMessage = 'Connected to dispatch';
      onStateChanged();

      mockService.addIceCandidate(
        callId: _callId!,
        sender: 'dispatch',
        candidate: {
          'candidate': 'candidate:456 1 udp 456 192.168.1.10 6000 typ host',
          'sdpMid': 'audio',
          'sdpMLineIndex': 0,
        },
      );
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    onStateChanged();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    onStateChanged();
  }

  Future<void> endCall() async {
    _isCalling = false;
    _remoteConnected = false;
    _statusMessage = 'Call ended';
    if (_callId != null) {
      mockService.endCall(callId: _callId!);
    }
    onStateChanged();
  }

  Future<Position> getLastKnownOrFetchLocation() async {
    return Position(
      latitude: -26.1345,
      longitude: 28.0476,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 1500.0,
      altitudeAccuracy: 5.0,
      heading: 180.0,
      headingAccuracy: 5.0,
      floor: null,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  void dispose() {}

  // Accessors for testing
  int? get callId => _callId;

  Map<String, dynamic>? getCallSessionDetails() {
    return _callId != null ? mockService.getCallSession(_callId!) : null;
  }

  List<Map<String, dynamic>> getCallIceCandidates() {
    return _callId != null ? mockService.getIceCandidates(_callId!) : [];
  }
}

/// Test-friendly EmergencyPage that uses MockDispatchController
class TestableEmergencyPage extends StatefulWidget {
  final MockDispatchController controller;

  const TestableEmergencyPage({super.key, required this.controller});

  @override
  State<TestableEmergencyPage> createState() => _TestableEmergencyPageState();
}

class _TestableEmergencyPageState extends State<TestableEmergencyPage> {
  late MockDispatchController controller;
  LatLng? _currentLatLng;
  final MapController _mapController = MapController();
  static const Color _brandRed = Colors.red;
  Color get _brandBlue => Colors.blue;
  final double _mapZoom = 15.0;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    controller.onStateChanged = () {
      if (mounted) setState(() {});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLocationForMap();
    });
  }

  Future<void> _fetchLocationForMap() async {
    if (_isFetchingLocation) return;
    _isFetchingLocation = true;
    try {
      final pos = await controller.getLastKnownOrFetchLocation();
      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentLatLng = newPos);
      if (mounted) {
        _mapController.move(newPos, _mapZoom);
      }
    } catch (_) {
    } finally {
      _isFetchingLocation = false;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_moon),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "Emergency • Incident ${controller.incidentId ?? "—"}",
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _fetchLocationForMap,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh location',
        )
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.grey[800],
              child: controller.isCalling
                  ? (controller.remoteConnected
                      ? const Icon(Icons.call, color: Colors.green, size: 34)
                      : controller.ringingPulse)
                  : const Icon(Icons.security, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              controller.statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            controller.isCalling ? _buildCallControls() : _buildCallButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return Card(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.incidentId != null ? "Your Location" : "Fetching location…",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: _fetchLocationForMap,
                  icon: const Icon(Icons.my_location),
                  tooltip: 'Recenter',
                )
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: _currentLatLng == null
                ? const Center(child: CircularProgressIndicator())
                : Container(color: Colors.grey[300]),
          ),
        ],
      ),
    );
  }

  Widget _buildHiddenRenderer() {
    return const SizedBox(width: 1, height: 1);
  }

  Widget _buildCallButton() {
    final canCall = controller.incidentId != null && !controller.isCalling;
    return ElevatedButton.icon(
      key: const Key('call-dispatch-button'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: canCall
          ? () {
              controller.startVoiceCallAndSignal().then((_) {
                if (mounted) setState(() {});
              });
              if (mounted) setState(() {});
            }
          : null,
      icon: const Icon(Icons.call),
      label: const Text("Call Dispatch", style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _controlCircle(
            icon: controller.isMuted ? Icons.mic_off : Icons.mic,
            label: controller.isMuted ? "Unmute" : "Mute",
            onTap: () {
              controller.toggleMute();
              if (mounted) setState(() {});
            }),
        _controlCircle(
            icon: controller.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
            label: "Speaker",
            onTap: () async {
              await controller.toggleSpeaker();
              if (mounted) setState(() {});
            }),
        _controlCircle(
            icon: Icons.call_end,
            label: "End",
            color: Colors.redAccent,
            onTap: () async {
              await controller.endCall();
              if (mounted) setState(() {});
            }),
      ],
    );
  }

  Widget _controlCircle({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? Colors.grey[800],
          ),
          child: IconButton(
            icon: Icon(icon),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildTopBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            children: [
              _buildHiddenRenderer(),
              _buildStatusCard(),
              const SizedBox(height: 12),
              _buildMapCard(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {},
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text("Chat with Dispatch", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Emergency dispatch flow enables call button after incident and starts call',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    final callButtonFinder = find.byKey(const Key('call-dispatch-button'));
    expect(callButtonFinder, findsOneWidget);
    
    // Initially button should be disabled (no incident)
    final ElevatedButton button = tester.widget(callButtonFinder);
    expect(button.onPressed, isNull);
    expect(find.text('Preparing emergency...'), findsOneWidget);

    // Manually trigger startup to create incident
    await mockController.startup();
    await tester.pumpAndSettle();

    // Button should now be enabled
    final ElevatedButton enabledButton = tester.widget(callButtonFinder);
    expect(enabledButton.onPressed, isNotNull);
    expect(find.text('Incident ready'), findsOneWidget);

    // Tap call button
    await tester.tap(callButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Connected to dispatch'), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);

    // Test mute
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_off), findsOneWidget);

    // End call
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle();
    expect(find.text('Call ended'), findsOneWidget);
  });

  testWidgets('Mock call service tracks incident and call sessions',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Simulate startup (incident created)
    await mockController.startup();
    await tester.pumpAndSettle();

    expect(mockController.incidentId, isNotNull);
    expect(mockController.statusMessage, 'Incident ready');

    // Start call and verify call session is created
    final callButtonFinder = find.byKey(const Key('call-dispatch-button'));
    await tester.tap(callButtonFinder);
    await tester.pump();

    expect(mockController.callId, isNotNull);
    final callSession = mockController.getCallSessionDetails();
    expect(callSession, isNotNull);
    expect(callSession!['status'], 'ringing');
    expect(callSession['offer_sdp'], 'mock-offer-sdp-v1');

    // Allow any pending dispatcher-answer simulation to complete before the test ends.
    await tester.pumpAndSettle();
  });

  testWidgets('Mock call service simulates dispatcher answer and remote connection',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Startup to create incident
    await mockController.startup();
    await tester.pumpAndSettle();

    // Start call (which triggers async dispatcher answer simulation)
    final callButtonFinder = find.byKey(const Key('call-dispatch-button'));
    await tester.tap(callButtonFinder);
    await tester.pump();

    // Wait for dispatcher answer simulation to complete.
    for (var i = 0; i < 10 && !mockController.remoteConnected; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // Verify remote is connected after answer
    expect(mockController.remoteConnected, true);
    expect(mockController.statusMessage, 'Connected to dispatch');

    final callSession = mockController.getCallSessionDetails();
    expect(callSession!['status'], 'answered');
    expect(callSession['answer_sdp'], 'mock-answer-sdp-v1');
  });

  testWidgets('Mock call service tracks ICE candidates from both parties',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Setup and start call
    await mockController.startup();
    await tester.pumpAndSettle();

    final callButtonFinder = find.byKey(const Key('call-dispatch-button'));
    await tester.tap(callButtonFinder);
    await tester.pump();

    // Allow time for ICE candidate simulation
    for (var i = 0; i < 10 && mockController.getCallIceCandidates().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final candidates = mockController.getCallIceCandidates();
    expect(candidates.length, greaterThanOrEqualTo(2));

    // Verify user candidate exists
    final userCandidate = candidates.firstWhere(
      (c) => c['sender'] == 'user',
      orElse: () => {},
    );
    expect(userCandidate, isNotEmpty);
    expect(userCandidate['candidate'].toString(), contains('127.0.0.1'));

    // Verify dispatcher candidate exists
    final dispatcherCandidate = candidates.firstWhere(
      (c) => c['sender'] == 'dispatch',
      orElse: () => {},
    );
    expect(dispatcherCandidate, isNotEmpty);
    expect(dispatcherCandidate['candidate'].toString(), contains('192.168.1.10'));
  });

  testWidgets('End call marks session as ended in mock service',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Setup call
    await mockController.startup();
    await tester.pumpAndSettle();

    final callButtonFinder = find.byKey(const Key('call-dispatch-button'));
    await tester.tap(callButtonFinder);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // End call
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle();

    // Verify call session marked as ended
    final callSession = mockController.getCallSessionDetails();
    expect(callSession!['status'], 'ended');
    expect(mockController.isCalling, false);
  });

  testWidgets('Emergency page shows incident placeholder and refresh button',
      (WidgetTester tester) async {
    final mockService = MockCallService();
    late MockDispatchController mockController;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            mockController = MockDispatchController(
              incidentId: null,
              context: context,
              mockService: mockService,
              onStateChanged: () {},
            );
            return TestableEmergencyPage(controller: mockController);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Emergency • Incident —'), findsOneWidget);
    expect(find.byTooltip('Refresh location'), findsOneWidget);
    expect(find.text('Fetching location…'), findsOneWidget);
  });
}