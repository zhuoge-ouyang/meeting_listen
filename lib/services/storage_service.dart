import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/transcription_models.dart';

class StorageService extends ChangeNotifier {
  Box<TranscriptionResult>? _box;

  Future initialize() async {
    _box = await Hive.openBox<TranscriptionResult>('transcriptions');
  }

  Future save(TranscriptionResult res) async {
    await _box!.put(res.sessionId, res);
    notifyListeners();
  }

  List<TranscriptionResult> getAll() {
    return _box!.values.toList().reversed.toList();
  }

  Future<void> delete(String sessionId) async {
    await _box!.delete(sessionId);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _box!.clear();
    notifyListeners();
  }
}