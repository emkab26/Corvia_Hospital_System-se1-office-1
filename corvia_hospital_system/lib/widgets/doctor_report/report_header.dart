import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_models.dart';

/// Collapsing [SliverAppBar] with an ECG pulse background painter.
/// Placed as the first sliver inside [DoctorReportScreen]'s [CustomScrollView].
class ReportHeader extends StatelessWidget {
  final ReportData report;

  const ReportHeader({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      elevation: 0,
      backgroundColor: context.cBgSecondary,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: context.cTextPrimary,
          size: 18,
        ),
        onPressed: () => Navigator.maybePop(context),
        tooltip: 'Back',
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.share_rounded,
              color: context.cTextSecondary, size: 20),
          onPressed: () {},
          tooltip: 'Share',
        ),
        IconButton(
          icon: Icon(Icons.more_vert_rounded,
              color: context.cTextSecondary, size: 20),
          onPressed: () => _showMenu(context),
          tooltip: 'More options',
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Medical Report',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Visit · ${report.visitDate}',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        background: _EcgBackground(),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: CorviaColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _menuItem(context, Icons.print_rounded, 'Print Report'),
            _menuItem(context, Icons.download_rounded, 'Download PDF'),
            _menuItem(context, Icons.content_copy_rounded, 'Copy Patient ID'),
            _menuItem(
              context,
              Icons.flag_rounded,
              'Flag for Review',
              color: CorviaColors.warning,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? context.cAccentReadable, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? context.cTextPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () => Navigator.pop(context),
    );
  }
}

// ── ECG background ────────────────────────────────────────────────────────────

class _EcgBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.cBgSecondary,
      child: CustomPaint(
        painter: _EcgPainter(accentColor: CorviaColors.accent),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  final Color accentColor;

  const _EcgPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.15)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // ECG pulse path
    final path = Path()
      ..moveTo(0, h * 0.60)
      ..lineTo(w * 0.14, h * 0.60)
      ..lineTo(w * 0.17, h * 0.28)
      ..lineTo(w * 0.21, h * 0.82)
      ..lineTo(w * 0.24, h * 0.60)
      ..lineTo(w * 0.42, h * 0.60)
      ..lineTo(w * 0.45, h * 0.33)
      ..lineTo(w * 0.49, h * 0.79)
      ..lineTo(w * 0.52, h * 0.60)
      ..lineTo(w * 0.70, h * 0.60)
      ..lineTo(w * 0.73, h * 0.30)
      ..lineTo(w * 0.77, h * 0.80)
      ..lineTo(w * 0.80, h * 0.60)
      ..lineTo(w, h * 0.60);

    canvas.drawPath(path, linePaint);

    // Subtle grid dots
    for (double x = 0; x < w; x += w * 0.05) {
      for (double y = h * 0.2; y < h; y += h * 0.15) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EcgPainter old) =>
      old.accentColor != accentColor;
}
