// Conditional-import shell. Resolves to the web implementation when
// `dart:html` is available; otherwise to a no-op stub. The recording
// screen only renders the web variant (guarded by `kIsWeb`).
export 'file_upload_widget_io.dart'
    if (dart.library.html) 'file_upload_widget_web.dart';
