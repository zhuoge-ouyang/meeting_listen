import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared date/time formatting and colour utilities used across multiple screens.
class RecordWiseDateUtils {
  RecordWiseDateUtils._();

  /// Parse an ISO-8601 string; falls back to [DateTime.now()] on error.
  static DateTime parseDateTime(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Full date + time label (used by HomeScreen list tiles).
  /// e.g. "Today 2:30 PM", "Yesterday 9:00 AM", "Monday 11:15 AM", "Dec 15, 2025 4:00 PM"
  static String formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date  = DateTime(dt.year, dt.month, dt.day);
    final time  = DateFormat('h:mm a').format(dt);

    if (date == today) {
      return 'Today $time';
    } else if (today.difference(date).inDays == 1) {
      return 'Yesterday $time';
    } else if (now.difference(dt).inDays < 7) {
      return '${DateFormat('EEEE').format(dt)} $time';
    } else {
      return DateFormat('MMM d, y h:mm a').format(dt);
    }
  }

  /// Date-only label (used by ResultsHistoryScreen).
  /// e.g. "Today", "Yesterday", "Monday", "Dec 15, 2025"
  static String formatDate(DateTime dt) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date  = DateTime(dt.year, dt.month, dt.day);

    if (date == today) return 'Today';
    if (today.difference(date).inDays == 1) return 'Yesterday';
    if (now.difference(dt).inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d, y').format(dt);
  }

  /// Time-only label. e.g. "2:30 PM"
  static String formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);

  /// Colour associated with a meeting-type badge.
  static Color meetingTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'meeting':    return Colors.blue;
      case 'interview':  return Colors.green;
      case 'lecture':    return Colors.orange;
      case 'call':       return Colors.purple;
      case 'brainstorm': return Colors.deepOrange;
      case 'chat':       return Colors.indigo;
      default:           return Colors.grey;
    }
  }
}
