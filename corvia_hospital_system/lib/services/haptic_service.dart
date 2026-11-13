import 'package:flutter/services.dart';

class HapticService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mycorvia/haptic');

  /// Queries the platform to check if haptic feedback/vibration is supported by the hardware.
  static Future<bool> isHapticSupported() async {
    try {
      final bool supported = await _channel.invokeMethod('isHapticSupported');
      return supported;
    } on PlatformException {
      return false; // Fall back to false on Web, Desktop or when channel is unavailable
    }
  }
}
