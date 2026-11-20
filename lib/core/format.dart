import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatPlayTime(int seconds) {
  if (seconds < 60) return seconds == 0 ? 'Sin jugar' : '< 1 min';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '$h h $m min' : '$m min';
}

String formatDateTime(DateTime date) =>
    DateFormat('d MMM y, HH:mm').format(date.toLocal());
