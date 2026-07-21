import 'dart:io';

import 'package:path/path.dart' as p;

import 'ass_parser.dart';
import 'srt_parser.dart';
import 'subtitle_document.dart';
import 'vtt_parser.dart';

class SubtitleLoader {
  static const exts = {'.ass', '.ssa', '.srt', '.vtt'};

  static Future<SubtitleDocument> load(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    return switch (ext) {
      '.ass' || '.ssa' => AssParser.parseFile(file),
      '.srt' => SrtParser.parseFile(file),
      '.vtt' => VttParser.parseFile(file),
      _ => throw UnsupportedError('不支持的字幕格式: $ext'),
    };
  }
}
