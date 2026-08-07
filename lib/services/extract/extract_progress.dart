double? parseMkvextractFraction(String output) {
  final matches = RegExp(
    r'Progress:\s*(\d+(?:\.\d+)?)%',
    caseSensitive: false,
  ).allMatches(output);
  if (matches.isEmpty) return null;
  final percent = double.tryParse(matches.last.group(1)!);
  return percent == null ? null : (percent / 100).clamp(0.0, 1.0);
}

double? parseFfmpegFraction(String output, Duration duration) {
  if (RegExp(r'progress=end(?:\r?\n|$)').hasMatch(output)) return 1;
  if (duration.inMicroseconds <= 0) return null;

  final microsMatches = RegExp(r'out_time_(?:us|ms)=(\d+)').allMatches(output);
  int? micros;
  if (microsMatches.isNotEmpty) {
    micros = int.tryParse(microsMatches.last.group(1)!);
  } else {
    final timeMatches = RegExp(
      r'out_time=(\d+):(\d+):(\d+(?:\.\d+)?)',
    ).allMatches(output);
    if (timeMatches.isNotEmpty) {
      final match = timeMatches.last;
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = double.parse(match.group(3)!);
      micros = ((hours * 3600 + minutes * 60 + seconds) * 1000000).round();
    }
  }
  if (micros == null) return null;
  return (micros / duration.inMicroseconds).clamp(0.0, 1.0);
}
