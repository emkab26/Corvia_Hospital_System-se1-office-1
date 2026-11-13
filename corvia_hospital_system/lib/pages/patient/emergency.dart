import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../config/env.dart';
import 'emergency_phone_page.dart';
import 'emergency_intake_page.dart';
import '../../widgets/input_device_button.dart';
import '../../widgets/emergency_phone_card.dart';
import '../../services/windows_input_devices.dart';

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';

import 'package:latlong2/latlong.dart';

import '../../theme/app_theme.dart';

import '../../widgets/map_tiles.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../services/dispatch_call_controller.dart';

import 'chat_page_user.dart';

import 'package:flutter/services.dart';

/// Patient entry: phone fallback by default; explicit intake when enabled.

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({
    super.key,
    this.dispatchEnabled = Env.emergencyDispatchEnabled,
  });

  final bool dispatchEnabled;

  @override
  Widget build(BuildContext context) => dispatchEnabled
      ? const EmergencyIntakePage()
      : const EmergencyPhonePage();
}

/// Retained voice screen for legacy regression coverage. Normal app routing uses
/// explicit intake; this screen does not establish ER24 access.
class LegacyDispatchEmergencyPage extends StatefulWidget {
  const LegacyDispatchEmergencyPage({super.key});

  @override
  State<LegacyDispatchEmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<LegacyDispatchEmergencyPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late DispatchCallController controller;

  late AnimationController _pulseController;

  late Animation<double> _pulseAnimation;

  bool _isButtonPressed = false;

  LatLng? _currentLatLng;

  final MapController _mapController = MapController();

  static const Color _brandRed = CorviaColors.danger;

  // Accent is theme-dependent (palette can change at runtime), so resolve it

  // on each read rather than freezing it in a const/final.

  Color get _brandBlue => CorviaColors.accent;

  final double _mapZoom = 15.0;

  bool _isFetchingLocation = false;
  Position? _locationFix;
  bool _locationUnavailable = false;

  /// Starts optimistic so the prompt card never flashes on screen during the
  /// first status check. Only a confirmed "not granted" reveals it.
  bool _locationPermissionGranted = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    controller = DispatchCallController(
      incidentId: null,
      onStateChanged: () => mounted ? setState(() {}) : null,
      context: context,
    );

    controller.startup();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLocationPermissionStatus();

      _fetchLocationForMap();
    });
  }

  /// The user can grant location from the system settings screen and come back,
  /// so re-check on resume rather than leaving a stale prompt on an emergency
  /// screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocationPermissionStatus();
    }
  }

  Future<void> _refreshLocationPermissionStatus() async {
    try {
      final status = await Permission.location.status;

      if (!mounted) return;

      setState(() {
        _locationPermissionGranted = status.isGranted || status.isLimited;
      });
    } catch (e) {
      // Leave the flag as-is: assuming "denied" here would show the prompt to a
      // user who has already granted location.
      debugPrint('Emergency: could not read location permission status: $e');
    }
  }

  Future<void> _ensureLocationPermission() async {
    try {
      final status = await Permission.location.request();

      if (!mounted) return;

      final granted = status.isGranted || status.isLimited;

      setState(() => _locationPermissionGranted = granted);

      if (granted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Location enabled.')));

        await _fetchLocationForMap();
        return;
      }

      if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog(
          'Location permission blocked',
          'Emergency location sharing needs location access so responders can '
              'find you.\n\nPlease enable Location in your device settings.',
        );
      }
    } catch (e) {
      // Never silently swallow this: if the prompt cannot be shown, the user
      // must still be told how to enable location themselves.
      debugPrint('Emergency: location permission request failed: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't open the location prompt. Enable Location for Corvia in "
            'your device settings.',
          ),
        ),
      );
    }
  }

  void _showOpenSettingsDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.cBgSecondary,
        title: Text(title, style: TextStyle(color: context.cTextPrimary)),
        content: Text(message, style: TextStyle(color: context.cTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  /// Only built when location is actually missing - see the guard in build().
  Widget _buildLocationPermissionCard() {
    return Card(
      color: context.cBgSecondary,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location sharing in emergencies',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you trigger an emergency, Corvia shares your location with '
              'dispatch so responders can find you quickly. Enable location '
              'access to allow this.',
              style: TextStyle(color: context.cTextSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _ensureLocationPermission,
                  child: const Text('Enable location'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchLocationForMap() async {
    if (_isFetchingLocation) return;

    _isFetchingLocation = true;

    try {
      final pos = await controller.getLastKnownOrFetchLocation();

      if (!mounted) return;
      if (pos == null) {
        setState(() {
          _locationUnavailable = true;
          _currentLatLng = null;
          _locationFix = null;
        });
        return;
      }
      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _locationUnavailable = false;
        _locationFix = pos;
        _currentLatLng = newPos;
      });

      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        _mapController.move(newPos, _mapZoom);
      }
    } catch (_) {
      // ignore silently
    } finally {
      _isFetchingLocation = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _pulseController.dispose();

    controller.dispose();

    super.dispose();
  }

  // ------------------------------------------------------------------

  // TOP BAR

  // ------------------------------------------------------------------

  PreferredSizeWidget _buildTopBar() {
    return AppBar(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_moon, color: CorviaColors.danger),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "Emergency • Incident ${controller.incidentId ?? "-"}",
              style: TextStyle(
                color: CorviaColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        InputDeviceButton(
          label: 'microphone',
          selectedId: controller.microphoneId,
          enabled: !controller.isCalling || controller.remoteConnected,
          loadDevices: WindowsInputDevices.callMicrophones,
          onSelected: controller.selectMicrophone,
        ),
        IconButton(
          onPressed: _fetchLocationForMap,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh location',
        ),
      ],
    );
  }

  // ------------------------------------------------------------------

  // STATUS CARD

  // ------------------------------------------------------------------

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: CorviaColors.primaryDark,
              child: controller.isCalling
                  ? (controller.remoteConnected
                      ? Icon(
                          Icons.call,
                          color: CorviaColors.success,
                          size: 34,
                        )
                      : controller.ringingPulse)
                  : Icon(
                      Icons.security,
                      color: CorviaColors.accentLight,
                      size: 36,
                    ),
            ),
            const SizedBox(height: 14),
            if (controller.isCountingDown)
              Column(
                children: [
                  Text("Calling in ${controller.countdown}..."),
                  ElevatedButton(
                    onPressed: () {
                      controller.cancelCountdown();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              )
            else
              Text(
                controller.statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.cTextPrimary,
                ),
              ),
            const SizedBox(height: 18),
            controller.isCalling ? _buildCallControls() : _buildCallButton(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------

  // MAP CARD (NEW API)

  // ------------------------------------------------------------------

  Widget _buildMapCard() {
    final center = _currentLatLng ?? LatLng(0, 0);

    return Card(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: CorviaColors.primaryDark,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: CorviaColors.accentLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationUnavailable
                        ? 'Location unavailable. Retry or tell dispatch your address.'
                        : _locationFix != null
                            ? 'Last location: ${_locationFix!.timestamp.toLocal()} '
                                '(accuracy ${_locationFix!.accuracy.round()} m)'
                            : 'Fetching location...',
                    style: TextStyle(
                      color: CorviaColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _fetchLocationForMap,
                  icon: Icon(
                    Icons.my_location,
                    color: CorviaColors.accentLight,
                  ),
                  tooltip: 'Recenter',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: _locationUnavailable
                ? const Center(child: Text('No location fix available.'))
                : _currentLatLng == null
                    ? Center(
                        child: CircularProgressIndicator(
                          color: CorviaColors.accent,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: _mapZoom,
                            minZoom: 3,
                            maxZoom: 18,
                          ),
                          children: [
                            mapTileLayer(),
                            mapAttribution(),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: center,
                                  width: 50,
                                  height: 50,
                                  child: const Icon(
                                    Icons.location_on,
                                    size: 40,
                                    color: CorviaColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------

  // HIDDEN RENDERER (AUDIO)

  // ------------------------------------------------------------------

  Widget _buildHiddenRenderer() {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(opacity: 0.01, child: controller.remoteRendererWidget),
    );
  }

  // ------------------------------------------------------------------

  // CONFIRMATION DIALOG STEP

  // ------------------------------------------------------------------

  void _showEmergencyConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: _brandRed, size: 28),
              SizedBox(width: 10),
              Text("Confirm Emergency"),
            ],
          ),
          content: const Text(
            "Are you sure you want to trigger emergency dispatch? This will immediately connect you with a live operator and stream your current location coordinates.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "Cancel",
                style: TextStyle(color: CorviaColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();

                setState(() => _isButtonPressed = true);

                HapticFeedback.heavyImpact();

                Future.delayed(const Duration(milliseconds: 150), () {
                  if (mounted) {
                    setState(() => _isButtonPressed = false);

                    controller.startVoiceCallAndSignal();
                  }
                });
              },
              child: const Text(
                "Confirm & Call",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------

  // CALL BUTTON

  // ------------------------------------------------------------------

  Widget _buildCallButton() {
    final canCall = controller.incidentId != null && !controller.isCalling;

    return GestureDetector(
      onTap: () {
        if (canCall) {
          _showEmergencyConfirmation();
        }
      },
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isButtonPressed
                ? 0.93
                : (canCall ? _pulseAnimation.value : 1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _isButtonPressed
                    ? Color.lerp(CorviaColors.danger, Colors.black, 0.18)!
                    : (canCall ? CorviaColors.danger : context.cTextMuted),
                boxShadow: canCall
                    ? [
                        BoxShadow(
                          color: CorviaColors.danger.withValues(
                            alpha: _isButtonPressed ? 0.2 : 0.55,
                          ),
                          blurRadius: _isButtonPressed ? 8 : 20,
                          spreadRadius: _isButtonPressed ? 1 : 4,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.call, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    "Call Dispatch",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------

  // CALL CONTROLS

  // ------------------------------------------------------------------

  Widget _buildCallControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _controlCircle(
          icon: controller.isMuted ? Icons.mic_off : Icons.mic,
          label: controller.isMuted ? "Unmute" : "Mute",
          onTap: controller.toggleMute,
        ),
        _controlCircle(
          icon: controller.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
          label: "Speaker",
          onTap: controller.toggleSpeaker,
        ),
        _controlCircle(
          icon: Icons.call_end,
          label: "End",
          color: CorviaColors.danger,
          onTap: controller.endCall,
        ),
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
            color: color ?? CorviaColors.primaryDark,
            border: Border.all(
              color: CorviaColors.textMuted.withValues(alpha: 0.3),
            ),
          ),
          child: IconButton(
            icon: Icon(icon, color: CorviaColors.textPrimary),
            onPressed: onTap,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: CorviaColors.textSecondary)),
      ],
    );
  }

  int? _incidentIdAsInt() {
    final id = controller.incidentId;

    if (id == null) return null;

    return int.tryParse(id.toString());
  }

  // ------------------------------------------------------------------

  // MAIN BUILD

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final incidentId = _incidentIdAsInt();

    return Scaffold(
      appBar: _buildTopBar(),
      backgroundColor: context.cBgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            children: [
              _buildHiddenRenderer(),
              const EmergencyPhoneCard(),
              const SizedBox(height: 12),
              _buildStatusCard(),
              const SizedBox(height: 12),
              _buildMapCard(),

              // Only surfaced when location is actually missing. Showing it
              // unconditionally would tell users to enable a permission they
              // have already granted.
              if (!_locationPermissionGranted) ...[
                const SizedBox(height: 8),
                _buildLocationPermissionCard(),
              ],

              const SizedBox(height: 20),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.cDivider,
                  disabledForegroundColor: context.cTextMuted,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: incidentId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatPageUser(incidentId: incidentId),
                          ),
                        );
                      },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text(
                  "Chat with Dispatch",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
