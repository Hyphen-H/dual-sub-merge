import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ass_parser.dart';
import 'srt_parser.dart';
import 'subtitle_document.dart';
import 'text_decoder.dart';
import 'vtt_parser.dart';

enum SubtitleFormat { ass, srt, vtt }

class SubtitleLoader {
  static const exts = {'.ass', '.ssa', '.srt', '.vtt'};

  /// Parsed documents keyed by path and invalidated by size + mtime. Scanning a
  /// large folder repeatedly (after rename / merge / extract) no longer parses
  /// every file again.
  static final Map<String, _CacheEntry> _cache = {};
  static const _maxEntries = 600;

  static Future<SubtitleDocument> load(File file) async {
    final entry = await _entryFor(file);
    final text = entry.text ??= SubtitleTextDecoder.decode(
      await file.readAsBytes(),
    );
    return entry.doc ??= _parse(text, file.path);
  }

  /// Decoded text, cached for cheap bilingual/role pre-checks.
  static Future<String> readText(File file) async {
    final entry = await _entryFor(file);
    return entry.text ??= SubtitleTextDecoder.decode(await file.readAsBytes());
  }

  /// Cheap gate for bilingual detection. ASS/SSA files are only parsed when a
  /// dialogue line contains `\N` or looks like single-line mixed CN + Latin;
  /// other formats are always parsed (their line breaks live inside cue text).
  static Future<bool> mayContainBilingual(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext != '.ass' && ext != '.ssa') return true;
    final text = await readText(file);
    if (text.contains(r'\N')) return true;
    final han = RegExp(r'[\u4e00-\u9fff]');
    final latin = RegExp(r'[A-Za-z]{2,}');
    for (final line in const LineSplitter().convert(text)) {
      if (!line.toLowerCase().startsWith('dialogue:')) continue;
      final body = _dialogueText(line);
      if (body == null) continue;
      if (han.hasMatch(body) && latin.allMatches(body).length >= 3) {
        return true;
      }
    }
    return false;
  }

  static String? _dialogueText(String line) {
    var commas = 0;
    for (var i = 0; i < line.length; i++) {
      if (line.codeUnitAt(i) != 0x2C) continue;
      commas++;
      if (commas == 9) return line.substring(i + 1);
    }
    return null;
  }

  static void clearCache() => _cache.clear();

  static Future<_CacheEntry> _entryFor(File file) async {
    final stat = await file.stat();
    final key = _pathKey(file.path);
    final existing = _cache[key];
    if (existing != null &&
        existing.size == stat.size &&
        existing.modifiedMs == stat.modified.millisecondsSinceEpoch) {
      return existing;
    }
    final entry = _CacheEntry(
      size: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    );
    _cache[key] = entry;
    if (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return entry;
  }

  static String _pathKey(String path) {
    final key = p.normalize(p.absolute(path));
    return Platform.isWindows ? key.toLowerCase() : key;
  }

  static SubtitleDocument _parse(String text, String path) {
    return switch (detectText(text, extension: p.extension(path))) {
      SubtitleFormat.ass => AssParser.parse(text, sourcePath: path),
      SubtitleFormat.srt => SrtParser.parse(text, sourcePath: path),
      SubtitleFormat.vtt => VttParser.parse(text, sourcePath: path),
    };
  }

  static SubtitleFormat detectText(String text, {String extension = ''}) {
    final normalized = text.replaceFirst('\uFEFF', '').trimLeft();
    final lower = normalized.toLowerCase();
    if (lower.startsWith('[script info]') ||
        (lower.contains('[events]') && lower.contains('dialogue:'))) {
      return SubtitleFormat.ass;
    }
    if (lower.startsWith('webvtt')) return SubtitleFormat.vtt;
    return switch (extension.toLowerCase()) {
      '.ass' || '.ssa' => SubtitleFormat.ass,
      '.vtt' => SubtitleFormat.vtt,
      _ => SubtitleFormat.srt,
    };
  }

  /// Repairs only old extraction outputs whose content is ASS but suffix is SRT.
  static Future<File> repairExtractedExtension(File file) async {
    if (p.extension(file.path).toLowerCase() != '.srt' ||
        !p
            .basenameWithoutExtension(file.path)
            .toLowerCase()
            .endsWith('.extracted')) {
      return file;
    }
    final text = await readText(file);
    if (detectText(text, extension: '.srt') != SubtitleFormat.ass) return file;
    final target = File('${p.withoutExtension(file.path)}.ass');
    if (target.existsSync()) return file;
    try {
      return await file.rename(target.path);
    } catch (_) {
      return file;
    }
  }
}

class _CacheEntry {
  _CacheEntry({required this.size, required this.modifiedMs});

  final int size;
  final int modifiedMs;
  String? text;
  SubtitleDocument? doc;
}
