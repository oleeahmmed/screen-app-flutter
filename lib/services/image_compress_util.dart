import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:swipelab_webp/swipelab_webp.dart';

/// Max width sent to the server (matches backend SCREENSHOT_MAX_WIDTH).
const int kScreenshotMaxUploadWidth = 1080;

/// WebP quality for uploads — visually ~JPEG Q90 at much smaller size.
const int kScreenshotWebpQuality = 84;

/// Resize and encode monitor captures to lossy WebP via native libwebp.
Uint8List compressToWebP(
  Uint8List inputBytes, {
  int maxWidth = kScreenshotMaxUploadWidth,
  int quality = kScreenshotWebpQuality,
}) {
  try {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;

    img.Image resized = decoded;
    if (decoded.width > maxWidth) {
      resized = img.copyResize(
        decoded,
        width: maxWidth,
        interpolation: img.Interpolation.cubic,
      );
    }

    // Ensure RGBA for libwebp encoder.
    final rgbaImage = resized.numChannels == 4
        ? resized
        : resized.convert(numChannels: 4);
    final rgba = rgbaImage.getBytes(order: img.ChannelOrder.rgba);

    final webp = WebPEncoder.encodeRgba(
      rgba: rgba,
      width: rgbaImage.width,
      height: rgbaImage.height,
      quality: quality.toDouble(),
    );
    if (webp != null && webp.isNotEmpty) return webp;

    // Fallback if native WebP encoder unavailable.
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return inputBytes;
  }
}

/// Legacy JPEG path — prefer [compressToWebP] for screenshot uploads.
Uint8List compressToJpeg(
  Uint8List inputBytes, {
  int maxWidth = kScreenshotMaxUploadWidth,
  int quality = 72,
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

bool isWebpBytes(List<int> bytes) {
  if (bytes.length < 12) return false;
  return bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
}

bool isJpegBytes(List<int> bytes) {
  return bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
}
