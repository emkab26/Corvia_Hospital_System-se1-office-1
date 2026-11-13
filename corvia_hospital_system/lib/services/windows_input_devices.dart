import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../widgets/input_device_button.dart';

class WindowsInputDevices {
  static const _speech = MethodChannel('speech_to_text_windows');

  static Future<List<InputDevice>> cameras() => _rtcDevices('videoinput');
  static Future<List<InputDevice>> callMicrophones() =>
      _rtcDevices('audioinput');

  static Future<List<InputDevice>> _rtcDevices(String kind) async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    final unique = <String, InputDevice>{};
    for (final d in devices.where((d) => d.kind == kind)) {
      if (d.deviceId.isEmpty || d.deviceId == 'default') continue;
      unique[d.deviceId] = InputDevice(d.deviceId,
          d.label.isEmpty ? 'Device ${unique.length + 1}' : d.label);
    }
    return unique.values.toList();
  }

  static Future<List<InputDevice>> speechMicrophones() async {
    final rows = await _speech.invokeListMethod<dynamic>('inputDevices') ?? [];
    return rows
        .map((row) => InputDevice(row['id'] as String, row['label'] as String))
        .toList();
  }

  static Future<void> selectSpeechMicrophone(String id) =>
      _speech.invokeMethod<void>('selectInputDevice', {'id': id});
}
