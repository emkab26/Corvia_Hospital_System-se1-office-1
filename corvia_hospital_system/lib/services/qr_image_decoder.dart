import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Runs in an isolate so decoding a camera frame cannot block the UI.
String? decodeQrImage(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final image = img.decodePng(bytes);
  if (image == null) return null;
  final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List());
  try {
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
  } on ReaderException {
    return null;
  }
}
