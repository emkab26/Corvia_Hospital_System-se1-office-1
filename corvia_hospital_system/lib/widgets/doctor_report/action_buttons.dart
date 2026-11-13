import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'report_models.dart';

class ActionButtons extends StatelessWidget {
  final ReportData report;

  const ActionButtons({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Print - secondary
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _onPrint(context),
            icon: Icon(Icons.print_rounded,
                size: 18, color: context.cAccentReadable),
            label: Text(
              'Print',
              style: TextStyle(color: context.cAccentReadable),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: context.cAccentReadable),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Download PDF - primary
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _onDownload(context),
            icon: const Icon(Icons.download_rounded,
                size: 18, color: Colors.white),
            label: const Text(
              'Download PDF',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CorviaColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onPrint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending to printer…')),
    );
    // TODO: integrate `printing` package (^5.x)
  }

  void _onDownload(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Generating PDF for ${report.patient.fullName}…'),
      ),
    );
    // TODO: integrate `pdf` + `printing` packages
  }
}
