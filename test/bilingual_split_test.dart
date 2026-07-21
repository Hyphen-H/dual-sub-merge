import 'dart:io';

import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/models/subtitle_cue.dart';
import 'package:dual_sub_merge/models/track_role.dart';
import 'package:dual_sub_merge/services/bilingual_convert_service.dart';
import 'package:dual_sub_merge/services/bilingual_split.dart';
import 'package:dual_sub_merge/models/ass_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BilingualSplit', () {
    test('splits \\N CN then EN', () {
      final pair = BilingualSplit.trySplitRaw(
        r'{\fn楷体}那么,直截了当地说{\r}\N{\fntahoma}So, let me get this straight.{\r}',
      );
      expect(pair, isNotNull);
      expect(plainOf(pair!.chinese), contains('那么'));
      expect(plainOf(pair.foreign), contains('straight'));
    });

    test('splits \\N EN then CN', () {
      final pair = BilingualSplit.trySplitRaw('Hello world tonight\n你好世界今晚');
      expect(pair, isNotNull);
      expect(pair!.foreign.toLowerCase(), contains('hello'));
      expect(pair.chinese, contains('你好'));
    });

    test('document convertible', () {
      final cues = List.generate(
        8,
        (i) => SubtitleCue(
          startMs: i * 1000,
          endMs: i * 1000 + 500,
          rawText: r'中文对白句子啊\NEnglish dialogue line here.',
        ),
      );
      final r = BilingualSplit.splitDocument(cues);
      expect(r.convertible, isTrue);
      expect(r.splitOk, 8);
      expect(r.items.length, 16);
      expect(r.items.where((e) => e.role == TrackRole.chinese).length, 8);
      expect(r.items.where((e) => e.role == TrackRole.foreign).length, 8);
    });
  });

  group('BilingualConvertService', () {
    test('writes chs+eng.ass from dual file', () async {
      final dir = await Directory.systemTemp.createTemp('dual_sub_merge_bi_');
      addTearDown(() => dir.delete(recursive: true));

      final src = File(p.join(dir.path, 'Show.S01E01.ass'));
      final buf = StringBuffer()
        ..writeln('[Script Info]')
        ..writeln('ScriptType: v4.00+')
        ..writeln()
        ..writeln('[Events]')
        ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
      for (var i = 0; i < 6; i++) {
        buf.writeln(
          'Dialogue: 0,0:00:0$i.00,0:00:0$i.50,Default,,0,0,0,,'
          r'中文句子测试啊\NEnglish test line here.',
        );
      }
      await src.writeAsString(buf.toString());

      final svc = BilingualConvertService(MergeOptions(removeCredits: false));
      final r = await svc.convertFile(source: src, outDir: dir);
      expect(r.ok, isTrue, reason: r.message);
      final out = File(r.outputPath!);
      expect(out.existsSync(), isTrue);
      final text = await out.readAsString();
      expect(text, contains(StyleCatalog.chinese));
      expect(text, contains(StyleCatalog.foreign));
      expect(text, contains('中文句子测试啊'));
      expect(text, contains('English test line here.'));
      // source kept
      expect(src.existsSync(), isTrue);
    });
  });
}

String plainOf(String s) => s.replaceAll(RegExp(r'\{[^}]*\}'), '');
