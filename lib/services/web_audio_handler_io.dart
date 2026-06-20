import 'dart:typed_data';

/// Non-web stub. The recording path on mobile/desktop uses real file paths,
/// so blob-URL fetching is never invoked. If it ever is, return null.
class WebAudioHandler {
  static Future<Uint8List?> fetchBlobData(String blobUrl) async => null;
}
