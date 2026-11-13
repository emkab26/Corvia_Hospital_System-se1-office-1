import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';
import 'package:mycorvia/services/qr_image_decoder.dart';

void main() {
  test('decodes a reception payload from PNG camera frame bytes', () {
    const payload = 'CORVIA_CHECKIN|v=1|patient_id=test|appointment_id=123';
    final matrix = Encoder.encode(payload, ErrorCorrectionLevel.h).matrix!;
    const scale = 6;
    const margin = 4;
    final frame = img.Image(
        width: (matrix.width + margin * 2) * scale,
        height: (matrix.height + margin * 2) * scale);
    img.fill(frame, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) != 1) continue;
        img.fillRect(frame,
            x1: (x + margin) * scale,
            y1: (y + margin) * scale,
            x2: (x + margin + 1) * scale - 1,
            y2: (y + margin + 1) * scale - 1,
            color: img.ColorRgb8(0, 0, 0));
      }
    }
    expect(decodeQrImage(Uint8List.fromList(img.encodePng(frame))), payload);
  });

  test('blank and invalid frames produce no QR result', () {
    final blank = img.Image(width: 100, height: 100);
    expect(decodeQrImage(Uint8List.fromList(img.encodePng(blank))), isNull);
    expect(decodeQrImage(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
