import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../../services/health_service.dart';
import '../../services/wearable_link_service.dart';
import '../../theme/app_theme.dart';
import '../../auth/linked_devices_page.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

// Logger for debug and production-safe logging
final Logger _logger = Logger('CorviaWearableApp');

/// How often the page polls Health Connect / HealthKit while open. Samsung
/// Health → Health Connect typically syncs in 5–15 min batches, so 10 min is
/// a sensible default — frequent enough to feel "live", relaxed enough not
/// to drain the battery.
const Duration _kAutoRefreshInterval = Duration(minutes: 10);

/// Entry widget kept as a Scaffold (not a nested MaterialApp). The parent
/// MaterialApp's CorviaTheme already supplies the dark-blue look.
class CorviaWearableApp extends StatelessWidget {
  const CorviaWearableApp({super.key});

  @override
  Widget build(BuildContext context) => const WearableHome();
}

/// The main wearables dashboard showing live, auto-refreshing health data
/// pulled directly from Android Health Connect or Apple HealthKit via the
/// device's connected wearables.
class WearableHome extends StatefulWidget {
  const WearableHome({super.key});
  @override
  State<WearableHome> createState() => _WearableHomeState();
}

class _WearableHomeState extends State<WearableHome>
    with WidgetsBindingObserver {
  // ── Health-store state ────────────────────────────────────────────────────
  /// True once `HealthService.isAvailable()` returns true. On Android this
  /// means Health Connect is installed and reachable; on iOS it means
  /// HealthKit is present (always true on a real device).
  bool _sdkAvailable = false;

  /// True once the user has granted the Health Connect / HealthKit dialog.
  /// We pessimistically default to false and refresh on every page open.
  bool _permissionsGranted = false;

  /// Most-recent snapshot from `HealthService.snapshot()`. Null until the
  /// first successful read.
  HealthSnapshot? _snapshot;

  /// True while a refresh is in flight. Used to disable the refresh button
  /// and to show a top progress bar.
  bool _refreshing = false;

  /// Friendly status message rendered in the connection banner when we can't
  /// stream data (e.g. "Health Connect isn't installed", "Permissions
  /// denied"). Null when everything's working.
  String? _statusMessage;

  /// Set when Health Connect itself throws during init (IPC failure, bad APK
  /// state, OEM crash) rather than merely being absent or unpermissioned.
  /// Drives the error banner, whose Retry taps straight back into [_initHealth].
  String? _healthError;

  /// Auto-poll timer — fires every [_kAutoRefreshInterval] while the page is
  /// mounted. Pauses when the app is backgrounded; resumes on resume.
  Timer? _autoRefresh;

  // ── Display animation state ───────────────────────────────────────────────
  /// Smoothly-animated value that the BPM card displays; tracks the latest
  /// reading from `_snapshot.heartRate.bpm`.
  int _displayedHeart = 0;
  Timer? _displayTick;

  // ── Sparkline / history ───────────────────────────────────────────────────
  /// Last 60 readings for the sparkline. Filled in as fresh polls arrive.
  final List<double> hrHistory =
      List<double>.generate(60, (_) => 0, growable: true);

  // Table for steps graph
  final List<MetricHistoryData> _historicalSteps = [];

  // ── Other UI state ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initServices();
    _startDisplayTick();

    // Rebuild when the user links/unlinks a device so the banner refreshes.
    WearableLinkService.instance.addListener(_onLinkChanged);
    if (!kIsWeb && !WearableLinkService.instance.isInitialized) {
      WearableLinkService.instance.init();
    }
  }

  void _onLinkChanged() {
    if (mounted) setState(() {});
  }

  /// Re-poll when the app returns to the foreground — covers the common case
  /// of "user opened Samsung Health, granted Corvia access, came back".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  // ── Service init ──────────────────────────────────────────────────────────
  Future<void> _initServices() async {
    // Initialize health monitoring services.
    // Health Connect read permissions are requested separately via HealthService.

    await _initHealth();

    if (kIsWeb) return;

    // Begin the auto-refresh cadence. The Timer fires after the interval,
    // not immediately, so the first refresh comes from `_initHealth` above.
    _autoRefresh?.cancel();
    _autoRefresh = Timer.periodic(_kAutoRefreshInterval, (_) => _refresh());
  }

  /// Bootstraps Health Connect (Android) / HealthKit (iOS) and requests
  /// permission the first time. On subsequent app launches the OS remembers
  /// the grant; we just verify and refresh.
  Future<void> _initHealth() async {
    // Clear any previous error so a retry starts from a clean slate.
    if (mounted) setState(() => _healthError = null);

    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _sdkAvailable = false;
          _permissionsGranted = false;
          _statusMessage =
              'Wearable sync is available in the Corvia Android and iOS apps.';
        });
      }
      return;
    }

    // A throw here means Health Connect itself is broken, not merely absent or
    // unpermissioned — surface it in the banner instead of a blank screen.
    try {
      final available = await HealthService.instance.isAvailable();
      if (!mounted) return;
      setState(() => _sdkAvailable = available);

      if (!available) {
        final needsUpdate =
            await HealthService.instance.needsHealthConnectUpdate();
        if (!mounted) return;
        setState(() {
          _statusMessage = needsUpdate
              ? 'Update Health Connect from the Play Store to sync with your watch.'
              : 'Install Health Connect to read live data from your Samsung Watch.';
        });
        return;
      }

      final has = await HealthService.instance.hasPermissions();
      if (!mounted) return;

      if (has == true) {
        setState(() {
          _permissionsGranted = true;
          _statusMessage = null;
        });
        await _refresh();
        return;
      }

      // First-time or revoked — prompt the OS dialog.
      final granted = await HealthService.instance.requestPermissions();
      if (!mounted) return;
      setState(() {
        _permissionsGranted = granted;
        _statusMessage = granted
            ? null
            : 'Corvia needs Health Connect read access to show your watch data.';
      });
      if (granted) await _refresh();
    } catch (e) {
      _logger.warning('Health Connect init failed: $e');
      if (!mounted) return;
      setState(() {
        _healthError = 'Health Connect encountered an error. Tap to retry.';
      });
    }
  }

  /// Polls Health Connect for a fresh snapshot. Safe to call repeatedly —
  /// no-ops when the SDK isn't ready or a refresh is already in flight.
  Future<void> _refresh() async {
    if (!_sdkAvailable || !_permissionsGranted) return;
    if (_refreshing) return;
    if (!mounted) return;

    setState(() => _refreshing = true);
    try {
      final snap = await HealthService.instance.snapshot();
      final currentDate = DateTime.now();
      final todayMidnight =
          DateTime(currentDate.year, currentDate.month, currentDate.day);

      // UPDATE:
      // Fetch historical steps for the chart
      final List<MetricHistoryData> resolvedHistory = [];
      final DateFormat chartLabelFormat = DateFormat('E');

      // Start from 6 days ago
      final startDate = todayMidnight.subtract(const Duration(days: 6));

      for (int i = 0; i < 7; i++) {
        final dayStart =
            DateTime(startDate.year, startDate.month, startDate.day + i);

        // IMPORTANT: End time is START of next day (not end of current day)
        final dayEnd =
            DateTime(dayStart.year, dayStart.month, dayStart.day + 1);

        final steps =
            await HealthService.instance.getDailySteps(dayStart, dayEnd);

        resolvedHistory.add(
          MetricHistoryData(
            label: chartLabelFormat.format(dayStart),
            value: steps.toDouble(),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _snapshot = snap;
        _historicalSteps.clear();
        _historicalSteps.addAll(resolvedHistory);

        if (snap.hasHeartRate) {
          hrHistory.removeAt(0);
          hrHistory.add(snap.heartRate!.bpm.toDouble());
        }
      });
    } catch (e) {
      _logger.warning('Health snapshot/history failed: $e');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// User-triggered refresh — same as the auto-poll but shows a SnackBar
  /// when there's no fresh data so they know the tap registered.
  Future<void> _manualRefresh() async {
    if (!_sdkAvailable) {
      // Try to launch the Play Store flow for Health Connect.
      await HealthService.instance.installHealthConnect();
      await _initHealth();
      return;
    }
    if (!_permissionsGranted) {
      await _initHealth();
      return;
    }
    await _refresh();
    if (!mounted) return;
    final hr = _snapshot?.heartRate;
    final ageText = hr == null
        ? 'No heart-rate readings in the last hour. Make sure your watch is on your wrist.'
        : 'Latest reading: ${hr.bpm} BPM (${_relativeTime(hr.sampledAt)} ago, from ${hr.source}).';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ageText),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  // Smooth animation for displayed heart rate.
  void _startDisplayTick() {
    _displayTick?.cancel();
    _displayTick = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final target = _snapshot?.heartRate?.bpm ?? 0;
      if (_displayedHeart == target) return;
      setState(() {
        if (_displayedHeart < target) {
          _displayedHeart += 1;
        } else if (_displayedHeart > target) {
          _displayedHeart -= 1;
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefresh?.cancel();
    _displayTick?.cancel();
    WearableLinkService.instance.removeListener(_onLinkChanged);
    super.dispose();
  }

  // Metric card widget (heart rate, steps, location, calories)
  Widget _metricCard(IconData icon, String val, String unit, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 130),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: CorviaColors.secondaryDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                val,
                key: ValueKey(val),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: CorviaColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (unit.isNotEmpty)
            Text(unit,
                style: TextStyle(fontSize: 11, color: CorviaColors.textMuted)),
        ],
      ),
    );
  }

  Widget _connectionBanner() {
    final link = WearableLinkService.instance;
    final hasLinkedDevice = link.hasLinkedDevice;
    final firstDevice = hasLinkedDevice ? link.devices.first : null;
    final hr = _snapshot?.heartRate;
    final hasFreshData = hr != null && hr.age < const Duration(minutes: 30);

    // ── Health Connect errored during init ───────────────────────────────
    if (_healthError != null) {
      return _bannerShell(
        color: CorviaColors.danger,
        icon: Icons.error_outline,
        body: _healthError!,
        actionLabel: 'Retry',
        onActionTap: _initHealth,
      );
    }

    // ── Streaming fresh data ─────────────────────────────────────────────
    if (hasFreshData) {
      return _bannerShell(
        color: CorviaColors.success,
        icon: Icons.watch,
        body: hasLinkedDevice
            ? '${firstDevice!.name} → ${hr.source} • last reading ${_relativeTime(hr.sampledAt)} ago.'
            : '${hr.source} • last reading ${_relativeTime(hr.sampledAt)} ago.',
      );
    }

    // ── SDK unavailable (Health Connect not installed / outdated) ────────
    if (!_sdkAvailable) {
      return _bannerShell(
        color: CorviaColors.warning,
        icon: Icons.warning_amber_rounded,
        body: _statusMessage ?? 'Health Connect not available on this device.',
        actionLabel: kIsWeb ? null : 'Install',
      );
    }

    // ── Permissions not yet granted ──────────────────────────────────────
    if (!_permissionsGranted) {
      return _bannerShell(
        color: CorviaColors.warning,
        icon: Icons.lock_outline,
        body: _statusMessage ??
            'Grant Corvia read access in Health Connect to see your watch data.',
        actionLabel: 'Grant',
      );
    }

    // ── Permissions granted but no recent samples ────────────────────────
    if (hr == null) {
      return _bannerShell(
        color: CorviaColors.accent,
        icon: Icons.watch,
        body: hasLinkedDevice
            ? '${firstDevice!.name} linked. Open Samsung Health (or your watch app) to make sure step and heart-rate sync to Health Connect, then we will show them here.'
            : 'Waiting for your watch to publish steps and heart-rate to Health Connect / Apple Health.',
      );
    }

    // ── Stale data (>30 min old) ─────────────────────────────────────────
    return _bannerShell(
      color: CorviaColors.warning,
      icon: Icons.access_time,
      body:
          'Last reading was ${_relativeTime(hr.sampledAt)} ago — put your watch back on for live updates.',
    );
  }

  Widget _bannerShell({
    required Color color,
    required IconData icon,
    required String body,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Explicit callback wins (used by the error banner's Retry);
            // otherwise "Install"/"Grant" route through the health init flow
            // and any other tap opens the linked-devices page.
            if (onActionTap != null) {
              onActionTap();
            } else if (actionLabel == 'Install' || actionLabel == 'Grant') {
              _manualRefresh();
            } else {
              _openLinkedDevices();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    body,
                    style: TextStyle(
                      color: CorviaColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: color, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openLinkedDevices() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LinkedDevicesPage()),
    );
  }

  // New widget that fuses the previous _dashboardView() and _sensorsView() widgets
  Widget _homeView(double w) {
    final bpm = _snapshot?.heartRate?.bpm ?? 0;
    final steps = _snapshot?.stepsToday ?? 0;
    final calories = _snapshot?.caloriesToday ?? 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _connectionBanner(),

            const SizedBox(height: 20),

            Icon(
              Icons.health_and_safety,
              size: 80,
              color: CorviaColors.accent,
            ),
            // New updated header
            const SizedBox(height: 12),

            Text(
              'Health Dashboard',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: context.cTextPrimary,
              ),
            ),

            const SizedBox(height: 20),

            // Metrics
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                // Heart Rate Metric UI block
                _metricCard(
                  Icons.favorite,
                  bpm > 0 ? '$bpm' : '--',
                  'BPM',
                  CorviaColors.danger,
                ),
                // Steps Metric UI block
                _metricCard(
                  Icons.directions_walk,
                  steps > 0 ? '$steps' : '--',
                  'Steps',
                  CorviaColors.success,
                ),
                // Calories Burned display metric
                _metricCard(
                  Icons.local_fire_department,
                  calories > 0 ? '$calories' : '--',
                  'kcal',
                  CorviaColors.warning,
                ),
              ],
            ),

            const SizedBox(height: 20),

            _sparklineCard(
              'Heart Rate',
              hrHistory,
              CorviaColors.danger,
            ),

            HealthMetricHistoryChart(
              title: 'Activity History',
              unit: 'steps',
              data: _historicalSteps,
              color: CorviaColors.success,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // Sparkline chart card for historical data
  Widget _sparklineCard(String title, List<double> data, Color color) {
    final hasData = data.any((d) => d > 0);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CorviaColors.secondaryDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: CorviaColors.accentLight,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(
                hasData ? data.last.toStringAsFixed(0) : '—',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasData)
            SizedBox(
                height: 84,
                child: CustomPaint(painter: SparklinePainter(data, color)))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No data yet — readings appear here as your watch syncs.',
                style: TextStyle(color: CorviaColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Wearables'),
        actions: [
          IconButton(
            tooltip:
                _refreshing ? 'Refreshing…' : 'Refresh from Health Connect',
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: CorviaColors.textPrimary),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _manualRefresh,
          ),
          IconButton(
            tooltip: 'Linked Devices',
            icon: const Icon(Icons.watch),
            onPressed: _openLinkedDevices,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SafeArea(
          child: Stack(
            children: [
              _homeView(w),
              if (_refreshing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// Custom painter for sparkline charts
class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = color;

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = CorviaColors.textPrimary.withAlpha(5);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        bg);

    if (data.isEmpty) return;

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final range = (maxVal - minVal) == 0 ? 1 : (maxVal - minVal);
    final step = size.width / (data.length - 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = step * i;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Fill below sparkline for visual effect
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withAlpha(15);
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, fill);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) => true;
}

/// Simple structure mapping a historical data item.
class MetricHistoryData {
  final String label; // e.g. "Mon", "Oct 12"
  final double value; // e.g. 8400.0 steps

  MetricHistoryData({required this.label, required this.value});
}

/// A comprehensive, custom historical chart designed to showcase aggregations
/// of metrics collected over a timeline (e.g. daily steps tracking).
/// Includes interactive touch/pan states to show metrics dynamically.
class HealthMetricHistoryChart extends StatefulWidget {
  final String title;
  final String unit;
  final List<MetricHistoryData> data;
  final Color color;

  const HealthMetricHistoryChart({
    super.key,
    required this.title,
    required this.unit,
    required this.data,
    required this.color,
  });

  @override
  State<HealthMetricHistoryChart> createState() =>
      _HealthMetricHistoryChartState();
}

// UPDATED:
class _HealthMetricHistoryChartState extends State<HealthMetricHistoryChart> {
  /// Index tracking what bar the user is actively tapping/holding down on.
  /// Set to -1 when no element is active.
  int _selectedIndex = -1;

  @override
  Widget build(BuildContext stateContext) {
    // Renamed context to avoid confusion
    final hasData = widget.data.isNotEmpty;
    final maxValue =
        hasData ? widget.data.map((e) => e.value).fold(0.0, max) : 1.0;
    final activeData =
        (_selectedIndex >= 0 && _selectedIndex < widget.data.length)
            ? widget.data[_selectedIndex]
            : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CorviaColors.secondaryDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row detailing chart metric title and reactive interaction output
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: CorviaColors.accentLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // Dynamic readout updates values whenever the user touches a bar
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  activeData != null
                      ? '${activeData.value.toStringAsFixed(0)} ${widget.unit} (${activeData.label})'
                      : 'Hold bar to inspect',
                  key: ValueKey(_selectedIndex),
                  style: TextStyle(
                    color: activeData != null
                        ? widget.color
                        : CorviaColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasData)
            // LayoutBuilder gives us concrete, real-time widget sizing constraints
            LayoutBuilder(
              builder: (context, constraints) {
                final Size widgetSize = Size(constraints.maxWidth, 140);

                return GestureDetector(
                  onTapDown: (details) =>
                      _handleTouch(details.localPosition, widgetSize),
                  onHorizontalDragUpdate: (details) =>
                      _handleTouch(details.localPosition, widgetSize),
                  onTapUp: (_) => setState(() => _selectedIndex = -1),
                  onHorizontalDragEnd: (_) =>
                      setState(() => _selectedIndex = -1),
                  child: SizedBox(
                    height: widgetSize.height,
                    width: widgetSize.width,
                    child: CustomPaint(
                      painter: InteractiveChartPainter(
                        data: widget.data,
                        maxValue: maxValue,
                        color: widget.color,
                        selectedIndex: _selectedIndex,
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No historical values found.',
                  style: TextStyle(color: CorviaColors.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Calculates which column coordinate bucket matches the user screen position coordinate.
  void _handleTouch(Offset localPosition, Size widgetSize) {
    if (widget.data.isEmpty) return;

    const double leftPadding = 8.0;

    final chartWidth = widgetSize.width - leftPadding;
    final barWidthRatio = chartWidth / widget.data.length;

    int closestIndex = -1;
    double closestDistance = double.infinity;

    for (int i = 0; i < widget.data.length; i++) {
      final barCenter = leftPadding + (i * barWidthRatio) + (barWidthRatio / 2);

      final distance = (localPosition.dx - barCenter).abs();

      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }

    if (closestIndex != -1 && closestIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = closestIndex;
      });
    }
  }
}

/// Custom Chart Painter handling low-level graphics coordinates rendering.
class InteractiveChartPainter extends CustomPainter {
  final List<MetricHistoryData> data;
  final double maxValue;
  final Color color;
  final int selectedIndex;

  InteractiveChartPainter({
    required this.data,
    required this.maxValue,
    required this.color,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double bottomPadding = 20.0;
    const double leftPadding = 8.0;
    final double chartHeight = size.height - bottomPadding;
    final double chartWidth = size.width - leftPadding;
    final double barWidthRatio = chartWidth / data.length;

    // 1. Draw Background Grid Lines
    final gridPaint = Paint()
      ..color = CorviaColors.textPrimary.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final labelStyle = TextStyle(
      color: CorviaColors.textMuted,
      fontSize: 10,
    );

    // Render 3 horizontal baseline grids (0%, 50%, 100% capacity)
    for (int i = 0; i <= 2; i++) {
      double yPos = chartHeight * (i / 2);
      canvas.drawLine(
          Offset(leftPadding, yPos), Offset(size.width, yPos), gridPaint);
    }

    // 2. Iterate and Paint Bars & Text labels
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final bool isSelected = i == selectedIndex;

      // Compute dimensional constraints per bar relative to data intensity
      final double normalizedHeight =
          maxValue > 0 ? (item.value / maxValue) * chartHeight : 0.0;

      final double xLeft =
          leftPadding + (i * barWidthRatio) + (barWidthRatio * 0.15);
      final double xRight =
          leftPadding + ((i + 1) * barWidthRatio) - (barWidthRatio * 0.15);
      final double yTop = chartHeight - normalizedHeight;
      final double yBottom = chartHeight;

      final Rect barRect = Rect.fromLTRB(xLeft, yTop, xRight, yBottom);
      final RRect roundedBar =
          RRect.fromRectAndRadius(barRect, const Radius.circular(4));

      // Visual accents applied when the item is inspected
      final barPaint = Paint()
        ..color = isSelected ? color : color.withValues(alpha: 0.65)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(roundedBar, barPaint);

      // Render X-Axis Label Strings
      final textPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: labelStyle.copyWith(
            color:
                isSelected ? CorviaColors.textPrimary : CorviaColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: barWidthRatio);

      // Centers text layout underneath respective metrics bar
      final double xTextPos =
          xLeft + ((xRight - xLeft) / 2) - (textPainter.width / 2);
      textPainter.paint(canvas, Offset(xTextPos, chartHeight + 4));
    }
  }

  @override
  bool shouldRepaint(covariant InteractiveChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.data != data;
  }
}
