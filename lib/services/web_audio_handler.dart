// Conditional-import shell. Resolves to the web implementation when
// `dart:html` is available; otherwise to a no-op stub used on
// mobile/desktop builds (where blob URLs do not exist).
export 'web_audio_handler_io.dart'
    if (dart.library.html) 'web_audio_handler_web.dart';
