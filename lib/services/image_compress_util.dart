import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Max width sent to the server (matches backend SCREENSHOT_MAX_WIDTH).
const int kScreenshotMaxUploadWidth = 1080;

/// JPEG quality for uploads — server stores as WebP; one lossy step on the backend.
const int kScreenshotUploadJpegQuality = 85;

/// Resize and encode monitor captures for upload (JPEG; server normalizes to WebP).
Uint8List compressScreenshotForUpload(
  Uint8List inputBytes, {
  int maxWidth = kScreenshotMaxUploadWidth,
  int quality = kScreenshotUploadJpegQuality,
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

    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (_) {
    return inputBytes;
  }
}

@Deprecated('Use compressScreenshotForUpload')
Uint8List compressToWebP(
  Uint8List inputBytes, {
  int maxWidth = kScreenshotMaxUploadWidth,
  int quality = kScreenshotUploadJpegQuality,
}) =>
    compressScreenshotForUpload(inputBytes, maxWidth: maxWidth, quality: quality);

@Deprecated('Use compressScreenshotForUpload')
Uint8List compressToJpeg(
  Uint8List inputBytes, {
  int maxWidth = kScreenshotMaxUploadWidth,
  int quality = 72,
}) =>
    compressScreenshotForUpload(inputBytes, maxWidth: maxWidth, quality: quality);

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
