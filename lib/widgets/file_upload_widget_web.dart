// Web-only implementation. The conditional-import facade in
// `file_upload_widget.dart` ensures this file is only compiled when
// `dart.library.html` is available (i.e. the Flutter web target).
//
// Implemented with `package:web` + `dart:js_interop` (the `dart:html`
// API is being phased out). The file is still web-only, so the
// `avoid_web_libraries_in_flutter` lint is suppressed by design.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../utils/constants.dart';

/// Widget for uploading audio files for transcription (web implementation).
class FileUploadWidget extends StatefulWidget {
  final void Function(Uint8List audioData, String fileName) onFileSelected;
  final bool isProcessing;

  const FileUploadWidget({
    super.key,
    required this.onFileSelected,
    this.isProcessing = false,
  });

  @override
  State<FileUploadWidget> createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  String? _selectedFileName;

  void _selectFile() {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'audio/*'
      ..multiple = false;

    input.onchange = ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) return;
      final file = files.item(0)!;

      // Reject anything bigger than the backend upload cap before we spend
      // time reading the bytes.
      const maxBytes = AppConstants.maxUploadFileSizeMb * 1024 * 1024;
      if (file.size > maxBytes) {
        final mb = (file.size / (1024 * 1024)).toStringAsFixed(1);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '文件过大：${mb}MB。上限是 ${AppConstants.maxUploadFileSizeMb}MB。',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _selectedFileName = file.name);

      file.arrayBuffer().toDart.then(
        (buffer) {
          final audioData = buffer.toDart.asUint8List();
          widget.onFileSelected(audioData, file.name);
        },
        onError: (Object e) {
          debugPrint('FileUploadWidget: read error — $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('读取文件失败：$e')),
            );
          }
        },
      );
    }).toJS;

    input.click();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.upload_file, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '上传音频文件',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '选择已有会议录音，上传后生成转写和纪要',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_selectedFileName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.audio_file, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedFileName!,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (widget.isProcessing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: widget.isProcessing ? null : _selectFile,
              icon: const Icon(Icons.folder_open),
              label: Text(
                _selectedFileName == null
                    ? '选择音频文件'
                    : '选择其他文件',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '支持格式：WAV、MP3、OGG、M4A',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
