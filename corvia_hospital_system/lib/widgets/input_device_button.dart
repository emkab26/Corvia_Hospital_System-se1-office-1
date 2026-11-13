import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class InputDevice {
  const InputDevice(this.id, this.label);
  final String id;
  final String label;
}

/// The empty ID always means the platform default, never a cached device index.
class InputDeviceButton extends StatelessWidget {
  const InputDeviceButton({
    super.key,
    required this.label,
    required this.loadDevices,
    required this.onSelected,
    this.selectedId = '',
    this.enabled = true,
    this.icon = Icons.settings_voice,
  });

  final String label;
  final String selectedId;
  final IconData icon;
  final bool enabled;
  final Future<List<InputDevice>> Function() loadDevices;
  final Future<void> Function(String id) onSelected;

  @override
  Widget build(BuildContext context) {
    if (!isWindowsDesktop) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Select $label',
      icon: Icon(icon),
      onPressed: enabled
          ? () => showDialog<void>(
                context: context,
                builder: (_) => _DeviceDialog(button: this),
              )
          : null,
    );
  }
}

class _DeviceDialog extends StatefulWidget {
  const _DeviceDialog({required this.button});
  final InputDeviceButton button;

  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  List<InputDevice> _devices = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await widget.button.loadDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not list devices. Check the connection and Windows privacy settings, then refresh.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String id) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.button.onSelected(id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not use that device. It may be disconnected, busy, or blocked in Windows privacy settings.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.button.selectedId;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('Select ${widget.button.label}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_loading || _saving) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!),
                ),
              if (!_loading) ...[
                for (final device in [
                  const InputDevice('', 'Default'),
                  ..._devices
                ])
                  ListTile(
                    leading: Icon(selected == device.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(device.label),
                    onTap: _saving ? null : () => _select(device.id),
                  ),
                if (_devices.isEmpty && _error == null)
                  const Text(
                      'No connected devices found. Connect a device and refresh.'),
                if (selected.isNotEmpty &&
                    !_devices.any((d) => d.id == selected))
                  const Text(
                      'The selected device is unavailable. Choose Default or another device.'),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _loading || _saving ? null : _refresh,
              child: const Text('Refresh')),
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
  }
}
