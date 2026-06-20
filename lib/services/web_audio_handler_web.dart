// Web-only implementation. The conditional-import facade in
// `web_audio_handler.dart` ensures this file is only compiled when
// `dart.library.html` is available (i.e. the Flutter web target).
//
// Implemented with `package:web` + `dart:js_interop` (the `dart:html`
// API is being phased out). The file is still web-only, so the
// `avoid_web_libraries_in_flutter` lint is suppressed by design.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebAudioHandler {
  /// Fetch audio bytes from a `blob:` URL.
  static Future<Uint8List?> fetchBlobData(String blobUrl) async {
    try {
      final response = await web.window.fetch(blobUrl.toJS).toDart;
      final blob = await response.blob().toDart;
      if (blob.size == 0) {
        debugPrint('WebAudioHandler: blob empty');
        return null;
      }
      final buffer = await blob.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } catch (e, st) {
      debugPrint('WebAudioHandler: fetch blob failed — $e\n$st');
      return null;
    }
  }
}
