import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mycorvia/services/windows_input_devices.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows microphone enumeration, selection and default restore',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('Checking Windows input devices'))));
    final devices = await WindowsInputDevices.speechMicrophones();
    debugPrint('Windows speech microphones: ${devices.length}');
    const channel = MethodChannel('speech_to_text_windows');
    final ready =
        await channel.invokeMethod<bool>('initialize', {'debugLogging': false});
    expect(ready, true,
        reason:
            'Windows SAPI must initialize before validating device switching');
    try {
      await WindowsInputDevices.selectSpeechMicrophone('');
      for (final device in devices) {
        await WindowsInputDevices.selectSpeechMicrophone(device.id);
      }
      await expectLater(
          WindowsInputDevices.selectSpeechMicrophone('disconnected-device'),
          throwsA(isA<PlatformException>()));
    } finally {
      await WindowsInputDevices.selectSpeechMicrophone('');
    }
  }, skip: !Platform.isWindows);

  testWidgets('Windows camera and call microphone devices can be enumerated',
      (tester) async {
    final cameras = await WindowsInputDevices.cameras();
    final warmup = await createPeerConnection({});
    await warmup.close();
    await warmup.dispose();
    final microphones = await WindowsInputDevices.callMicrophones();
    debugPrint(
        'Windows cameras: ${cameras.length}; call microphones: ${microphones.length}');
    for (final id in cameras.isEmpty ? <String>[] : ['', cameras.first.id]) {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {if (id.isNotEmpty) 'deviceId': id},
      });
      final frame =
          File('${(await getTemporaryDirectory()).path}/captureFrame.png');
      try {
        final bytes = await stream
            .getVideoTracks()
            .first
            .captureFrame()
            .timeout(const Duration(seconds: 15));
        expect(bytes.lengthInBytes, greaterThan(8));
        debugPrint(
            'Camera frame captured (${id.isEmpty ? 'default' : 'explicit device'})');
      } finally {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
        if (await frame.exists()) await frame.delete();
      }
    }
    // No network connection or call is made. Capture is immediately released.
    if (microphones.isNotEmpty) {
      final stream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
      try {
        await Helper.selectAudioInput(microphones.first.id);
        expect(stream.getAudioTracks(), isNotEmpty);
      } finally {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
      }
    }
  }, skip: !Platform.isWindows);
}
