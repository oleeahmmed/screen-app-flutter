import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Resize and encode to JPEG (cross-platform; used on Android & fallback).
Uint8List compressToJpeg(
  Uint8List inputBytes, {
  int maxWidth = 720,
  int quality = 70,
}) {
  try {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;

    img.Image resized = decoded;
    if (decoded.width > maxWidth) {
      resized = img.copyResize(decoded, width: maxWidth);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return inputBytes;
  }
}
