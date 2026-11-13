import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/wearable_link_service.dart';
import '../theme/app_theme.dart';

/// Manages the user's linked wearables (Samsung Watch, Apple Watch, Fitbit,
/// etc.) and which health-app sync source Corvia pulls data from.
class LinkedDevicesPage extends StatefulWidget {
  const LinkedDevicesPage({super.key});

  @override
  State<LinkedDevicesPage> createState() => _LinkedDevicesPageState();
}

class _LinkedDevicesPageState extends State<LinkedDevicesPage> {
  final _svc = WearableLinkService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    if (!_svc.isInitialized) _svc.init();
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _openLinkSheet() async {
    final type = await showModalBottomSheet<WearableType>(
      context: context,
      backgroundColor: context.cBgSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CorviaColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      'Link a Device',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    for (final t in WearableType.values)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CorviaColors.accent.withValues(alpha: 0.15),
                          child: Icon(t.icon, color: CorviaColors.accent),
                        ),
                        title: Text(t.label,
                            style: TextStyle(color: context.cTextPrimary)),
                        subtitle: Text(
                          'Syncs via ${t.suggestedSource.label}',
                          style: TextStyle(
                              color: context.cTextSecondary, fontSize: 12),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: CorviaColors.accentLight),
                        onTap: () => Navigator.pop(context, t),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (type == null || !mounted) return;
    await _nameAndAdd(type);
  }

  Future<void> _nameAndAdd(WearableType type) async {
    final ctrl = TextEditingController(text: type.label);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name your device'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device name',
            hintText: 'e.g. My Galaxy Watch 8',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Link'),
          ),
        ],
      ),
    );

    if (name == null || !mounted) return;
    await _svc.addDevice(name: name, type: type);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${name.isEmpty ? type.label : name} linked.')),
    );
  }

  Future<void> _removeDevice(LinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'Corvia will stop syncing data from "${device.name}". '
          'You can link it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: CorviaColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _svc.removeDevice(device.id);
  }

  Future<void> _pickSyncSource() async {
    final source = await showModalBottomSheet<SyncSource>(
      context: context,
      backgroundColor: context.cBgSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CorviaColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose Sync Source',
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    for (final s in SyncSource.values)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CorviaColors.accent.withValues(alpha: 0.15),
                          child: Icon(s.icon, color: CorviaColors.accent),
                        ),
                        title: Text(s.label,
                            style: TextStyle(color: context.cTextPrimary)),
                        subtitle: Text(s.description,
                            style: TextStyle(
                                color: context.cTextSecondary, fontSize: 12)),
                        trailing: _svc.syncSource == s
                            ? Icon(Icons.check, color: CorviaColors.success)
                            : null,
                        onTap: () => Navigator.pop(context, s),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;
    await _svc.setSyncSource(source);
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _svc.markSynced();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Synced from ${_svc.syncSource.label}.'
            : 'Link a device and choose a sync source first.'),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Linked Devices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openLinkSheet,
        backgroundColor: CorviaColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Link Device', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _sectionTitle(context, 'Sync source'),
          _syncSourceCard(),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Your devices'),
          if (_svc.devices.isEmpty)
            _emptyState()
          else
            ..._svc.devices.map(_deviceTile),
        ],
      ),
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────────

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: context.cAccentReadable,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _syncSourceCard() {
    final source = _svc.syncSource;
    final lastSync = _svc.lastSyncAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: context.cCardShadow, blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: CorviaColors.accent.withValues(alpha: 0.15),
                child: Icon(source.icon, color: CorviaColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.label,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 2),
                    Text(source.description,
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickSyncSource,
                child: const Text('Change'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  lastSync == null
                      ? 'Never synced.'
                      : 'Last synced ${DateFormat('d MMM, HH:mm').format(lastSync)}',
                  style: TextStyle(color: context.cTextSecondary, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _svc.isReadyToSync && !_busy ? _syncNow : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync),
                label: const Text('Sync Now'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: context.cCardShadow, blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.watch_off, size: 48, color: CorviaColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No devices linked yet',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Link Device" below to pair your Samsung Watch, Apple Watch, '
            'Fitbit, or other wearable.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.cTextSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(LinkedDevice device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: context.cCardShadow, blurRadius: 6),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: CorviaColors.accent.withValues(alpha: 0.15),
          child: Icon(device.type.icon, color: CorviaColors.accent),
        ),
        title: Text(device.name,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            )),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(device.type.label,
                style: TextStyle(color: context.cTextSecondary)),
            Text(
              device.lastSyncedAt == null
                  ? 'Not synced yet'
                  : 'Last synced ${DateFormat('d MMM, HH:mm').format(device.lastSyncedAt!)}',
              style: TextStyle(color: CorviaColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: CorviaColors.danger),
          tooltip: 'Remove',
          onPressed: () => _removeDevice(device),
        ),
      ),
    );
  }
}
