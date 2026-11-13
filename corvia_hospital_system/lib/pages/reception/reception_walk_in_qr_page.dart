import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/walk_in_qr_service.dart';
import '../../theme/app_theme.dart';

class ReceptionWalkInQrPage extends StatefulWidget {
  const ReceptionWalkInQrPage({super.key});

  @override
  State<ReceptionWalkInQrPage> createState() => _ReceptionWalkInQrPageState();
}

class _ReceptionWalkInQrPageState extends State<ReceptionWalkInQrPage> {
  final WalkInQrService _service = WalkInQrService();

  ReceptionWalkInQr? _qr;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final qr = await _service.loadReceptionQr();
      if (!mounted) return;
      setState(() => _qr = qr);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_qr?.exists == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Generate a new reception QR?'),
          content: const Text(
            'The current QR will stop working immediately. Only regenerate it '
            'if the existing code has been exposed or needs to be replaced.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Current QR'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Generate New QR'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final qr = await _service.generateReceptionQr();
      if (!mounted) return;
      setState(() => _qr = qr);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reception walk-in QR is ready.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '')
        .replaceAll(RegExp(r', code:.*$'), '')
        .replaceAll(')', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Reception Walk-in QR'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _generating ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null && _qr == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 58, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final qr = _qr;
    final payload = qr?.payload;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CorviaColors.divider),
          ),
          child: Column(
            children: [
              Icon(
                payload == null
                    ? Icons.qr_code_2_rounded
                    : Icons.approval_rounded,
                size: 44,
                color: CorviaColors.accent,
              ),
              const SizedBox(height: 12),
              Text(
                qr?.hospitalName ?? 'Hospital Reception',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                payload == null
                    ? 'No walk-in QR has been generated yet.'
                    : 'Patients without appointments can scan this code to join the walk-in queue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cTextSecondary, height: 1.4),
              ),
              if (payload != null) ...[
                const SizedBox(height: 22),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: payload,
                    size: 270,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  qr?.generatedAt == null
                      ? 'Active reception QR'
                      : 'Generated ${DateFormat('d MMM yyyy, HH:mm').format(qr!.generatedAt!.toLocal())}',
                  style: TextStyle(color: context.cTextSecondary),
                ),
              ],
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code_2_rounded),
          label: Text(
            _generating
                ? 'Generating...'
                : payload == null
                    ? 'Generate Reception QR'
                    : 'Generate New Reception QR',
          ),
        ),
        if (payload != null) ...[
          const SizedBox(height: 10),
          Text(
            'Regeneration is optional. The current code remains valid until a new one is generated.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.cTextSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
