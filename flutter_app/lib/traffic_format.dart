String formatByteCount(int value) => _formatBytes(value, suffix: '');

String formatByteRate(int value) => '${_formatBytes(value, suffix: '')}/s';

String _formatBytes(int rawValue, {required String suffix}) {
  final value = rawValue < 0 ? 0 : rawValue;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var amount = value.toDouble();
  var unit = 0;
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024;
    unit++;
  }
  final number = unit == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(1);
  return '$number ${units[unit]}$suffix';
}

String formatConnectionDuration(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(remainder)}'
      : '${two(minutes)}:${two(remainder)}';
}
