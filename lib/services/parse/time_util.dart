class TimeUtil {
  static int parseAss(String s) {
    // H:MM:SS.cs or H:MM:SS.cc
    final p = s.trim().split(':');
    if (p.length != 3) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final secParts = p[2].split(RegExp(r'[.,]'));
    final sec = int.tryParse(secParts[0]) ?? 0;
    var frac = 0;
    if (secParts.length > 1) {
      final f = secParts[1].padRight(3, '0').substring(0, 3);
      frac = int.tryParse(f) ?? 0;
      // ass uses centiseconds often (2 digits)
      if (secParts[1].length <= 2) {
        frac = (int.tryParse(secParts[1].padRight(2, '0').substring(0, 2)) ?? 0) * 10;
      }
    }
    return ((h * 3600 + m * 60 + sec) * 1000) + frac;
  }

  static int parseSrt(String s) {
    // HH:MM:SS,mmm
    final p = s.trim().split(':');
    if (p.length != 3) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final secParts = p[2].split(RegExp(r'[.,]'));
    final sec = int.tryParse(secParts[0]) ?? 0;
    final ms = int.tryParse((secParts.length > 1 ? secParts[1] : '0').padRight(3, '0').substring(0, 3)) ?? 0;
    return ((h * 3600 + m * 60 + sec) * 1000) + ms;
  }

  static String formatAss(int ms) {
    if (ms < 0) ms = 0;
    final cs = (ms / 10).round();
    final h = cs ~/ 360000;
    final m = (cs % 360000) ~/ 6000;
    final s = (cs % 6000) ~/ 100;
    final c = cs % 100;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${c.toString().padLeft(2, '0')}';
  }
}
