import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

/// Real hospital-laboratory verifier queue. Access is enforced by Batch 26/28.
class LabVerificationQueuePage extends StatefulWidget {
  const LabVerificationQueuePage({super.key});

  @override
  State<LabVerificationQueuePage> createState() => _LabVerificationQueuePageState();
}

class _LabVerificationQueuePageState extends State<LabVerificationQueuePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<_VerificationItem> _items = const [];

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
      final response = await _supabase.rpc('corvia_lab_worker_verification_queue');
      if (!mounted) return;
      final rows = response is List ? response : const [];
      setState(() {
        _items = rows.whereType<Map>().map((row) => _VerificationItem.fromJson(Map<String, dynamic>.from(row))).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _cleanError(error);
      });
    }
  }

  Future<void> _release(_VerificationItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Release verified result?'),
        content: Text('Release ${item.testName} for ${item.containerLabel} to the patient and ordering team?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Release result')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supabase.rpc('corvia_lab_worker_release_result', params: {'p_lab_result_id': item.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result released.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException(message: ', '').replaceAll(')', '');

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(title: const Text('Verification Queue')),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: CorviaColors.accent))
            : _error != null
                ? _QueueState(icon: Icons.lock_outline_rounded, title: 'Verification unavailable', body: _error!, action: _load)
                : _items.isEmpty
                    ? _QueueState(icon: Icons.task_alt_rounded, title: 'Queue is clear', body: 'There are no submitted results awaiting verification.', action: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _QueueIntro(count: _items.length);
                            }
                            final item = _items[index - 1];
                            return _ResultCard(item: item, onRelease: () => _release(item));
                          },
                        ),
                      ),
      );
}

class _VerificationItem {
  const _VerificationItem({required this.id, required this.testName, required this.containerLabel, required this.specimenType, required this.result, required this.enteredBy, required this.enteredAt});
  final String id;
  final String testName;
  final String containerLabel;
  final String specimenType;
  final String result;
  final String enteredBy;
  final DateTime? enteredAt;
  factory _VerificationItem.fromJson(Map<String, dynamic> json) => _VerificationItem(
        id: json['lab_result_id'].toString(),
        testName: json['test_name']?.toString() ?? 'Laboratory test',
        containerLabel: json['container_label']?.toString() ?? 'Specimen container',
        specimenType: json['specimen_type']?.toString() ?? 'Specimen',
        result: json['draft_result']?.toString() ?? '',
        enteredBy: json['entered_by_name']?.toString() ?? 'Lab worker',
        enteredAt: DateTime.tryParse(json['result_entered_at']?.toString() ?? ''),
      );
}

class _QueueIntro extends StatelessWidget {
  const _QueueIntro({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: context.cAccentReadable.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [Icon(Icons.verified_user_outlined, color: context.cAccentReadable), const SizedBox(width: 12), Expanded(child: Text('$count result${count == 1 ? '' : 's'} await verification. Releasing a result makes it visible outside the laboratory.', style: TextStyle(color: context.cTextPrimary, height: 1.35)))]),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item, required this.onRelease});
  final _VerificationItem item;
  final VoidCallback onRelease;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: context.cBgSecondary, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.cDivider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.testName, style: TextStyle(color: context.cTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('${item.containerLabel} · ${item.specimenType}', style: TextStyle(color: context.cTextSecondary)),
          const SizedBox(height: 14),
          Text('Submitted result', style: TextStyle(color: context.cTextSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          SelectableText(item.result, style: TextStyle(color: context.cTextPrimary, height: 1.4)),
          const SizedBox(height: 14),
          Text('Entered by ${item.enteredBy}${item.enteredAt == null ? '' : ' · ${_formatDate(item.enteredAt!)}'}', style: TextStyle(color: context.cTextSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onRelease, icon: const Icon(Icons.publish_rounded), label: const Text('Release verified result')),
        ]),
      );

  static String _formatDate(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _QueueState extends StatelessWidget {
  const _QueueState({required this.icon, required this.title, required this.body, required this.action});
  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function() action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: context.cAccentReadable, size: 54), const SizedBox(height: 14), Text(title, style: TextStyle(color: context.cTextPrimary, fontWeight: FontWeight.bold, fontSize: 20)), const SizedBox(height: 8), Text(body, textAlign: TextAlign.center, style: TextStyle(color: context.cTextSecondary)), const SizedBox(height: 16), FilledButton.icon(onPressed: action, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh'))]),
      ));
}
