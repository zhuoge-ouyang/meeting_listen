import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Non-web stub. The upload widget is only rendered on web (the recording
/// screen guards it with `kIsWeb`); this stub is here so the import resolves
/// on mobile/desktop builds.
class FileUploadWidget extends StatelessWidget {
  final void Function(Uint8List audioData, String fileName) onFileSelected;
  final bool isProcessing;

  const FileUploadWidget({
    super.key,
    required this.onFileSelected,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
