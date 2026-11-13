import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/corvia_wearable_snapshot.dart';

class WearableService {
  WearableService._();

  static final WearableService instance = WearableService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.mycorvia/wearable',
  );

  bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<int> getConnectedWatchCount() async {
    if (!isSupportedPlatform) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod<int>(
        'getConnectedWatchCount',
      );

      return result ?? 0;
    } on PlatformException catch (error) {
      debugPrint(
        'Wear OS connection check failed: '
        '${error.code} ${error.message}',
      );

      return 0;
    } catch (error) {
      debugPrint(
        'Wear OS connection check failed: $error',
      );

      return 0;
    }
  }

  Future<WearableSyncResult> syncSnapshot(
    CorviaWearableSnapshot snapshot,
  ) async {
    if (!isSupportedPlatform) {
      return const WearableSyncResult(
        success: false,
        message: 'Wear OS sync is only supported on Android.',
      );
    }

    try {
      final rawResult = await _channel.invokeMethod<dynamic>(
        'syncSnapshot',
        snapshot.toPlatformMap(),
      );

      if (rawResult is! Map) {
        return const WearableSyncResult(
          success: false,
          message: 'The Android wearable bridge returned '
              'an invalid response.',
        );
      }

      final result = Map<String, dynamic>.from(rawResult);

      return WearableSyncResult(
        success: result['success'] == true,
        message: result['success'] == true
            ? 'Corvia watch data synced.'
            : 'Corvia watch data was not synced.',
        path: result['path']?.toString(),
        uri: result['uri']?.toString(),
      );
    } on PlatformException catch (error) {
      return WearableSyncResult(
        success: false,
        message: error.message ?? 'Wear OS sync failed.',
        errorCode: error.code,
      );
    } catch (error) {
      return WearableSyncResult(
        success: false,
        message: 'Wear OS sync failed: $error',
      );
    }
  }
}

class WearableSyncResult {
  const WearableSyncResult({
    required this.success,
    required this.message,
    this.path,
    this.uri,
    this.errorCode,
  });

  final bool success;
  final String message;

  final String? path;
  final String? uri;
  final String? errorCode;
}
