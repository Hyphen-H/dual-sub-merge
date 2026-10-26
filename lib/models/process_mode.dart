import 'package:flutter/material.dart';

/// Subtitle processing mode chosen in the subtitle workspace control bar.
enum ProcessMode {
  /// Pair Chinese + foreign single-language subs into `.chs+eng.ass`.
  merge,

  /// Pair Chinese + Dubtitle subtitles into `.chs+eng_dub.ass`.
  dubMerge,

  /// Pair Chinese + Japanese only into `.chs+jpn.ass` with Dial styles.
  jpMerge,

  /// Convert `\N` dual-line subs into `.chs+eng.ass`.
  styleConvert,

  /// Convert Chinese-only subs into `{prefix}.chs.ass` with 中下HDRipad.
  chineseConvert,
}

extension ProcessModeInfo on ProcessMode {
  bool get isPairingMode => switch (this) {
    ProcessMode.merge || ProcessMode.dubMerge || ProcessMode.jpMerge => true,
    ProcessMode.styleConvert || ProcessMode.chineseConvert => false,
  };

  String get label => switch (this) {
    ProcessMode.merge => '中英配对',
    ProcessMode.dubMerge => '中英配',
    ProcessMode.jpMerge => '中日配对',
    ProcessMode.styleConvert => '样式转换',
    ProcessMode.chineseConvert => '中文转换',
  };

  IconData get icon => switch (this) {
    ProcessMode.merge => Icons.merge_type,
    ProcessMode.dubMerge => Icons.record_voice_over_outlined,
    ProcessMode.jpMerge => Icons.compare_arrows_rounded,
    ProcessMode.styleConvert => Icons.style,
    ProcessMode.chineseConvert => Icons.translate_rounded,
  };

  String get tooltip => switch (this) {
    ProcessMode.merge =>
      '中外单语字幕按文件名前缀配对，清洗文本后合并为 .chs+eng/jpn.ass（按外文语言命名），并统一 HDRipad 样式。',
    ProcessMode.dubMerge => '只把中文 + Dubtitle 字幕配成一对，输出 .chs+eng_dub.ass。',
    ProcessMode.jpMerge =>
      '只把中文 + 日文字幕配成一对，输出 .chs+jpn.ass；默认套用 Dial-CH / Dial-JP：中文在上、字号大，日文贴底、字号小。',
    ProcessMode.styleConvert =>
      '将每个字幕文件视为 \\N 上下双语，拆成中/外双轨，统一 HDRipad 样式写出 .chs+eng/jpn.ass（保留源文件）。',
    ProcessMode.chineseConvert =>
      '识别单中字幕（\\N 双语会拆出中文半边），统一为中下HDRipad 样式写出 .chs.ass；外文内容丢弃。',
  };

  /// Verb used in the primary button label.
  String get actionLabel => switch (this) {
    ProcessMode.merge => '开始中英配对',
    ProcessMode.dubMerge => '开始中英配',
    ProcessMode.jpMerge => '开始中日配对',
    ProcessMode.styleConvert => '开始转换',
    ProcessMode.chineseConvert => '开始中文化',
  };

  String get actionLabelWithRename => switch (this) {
    ProcessMode.merge => '改名并中英配对',
    ProcessMode.dubMerge => '改名并中英配',
    ProcessMode.jpMerge => '改名并中日配对',
    ProcessMode.styleConvert => '改名并转换',
    ProcessMode.chineseConvert => '改名并中文化',
  };

  /// Progress/log wording for one group.
  String get workingLabel => switch (this) {
    ProcessMode.merge => '中英配对',
    ProcessMode.dubMerge => '中英配',
    ProcessMode.jpMerge => '中日配对',
    ProcessMode.styleConvert => '转换双语',
    ProcessMode.chineseConvert => '中文化',
  };

  String get skipDialogTitle => switch (this) {
    ProcessMode.merge => '部分中英字幕无法配对',
    ProcessMode.dubMerge => '部分 Dubtitle 字幕无法配对',
    ProcessMode.jpMerge => '部分中日字幕无法配对',
    ProcessMode.styleConvert => '部分文件无法转换',
    ProcessMode.chineseConvert => '部分字幕无法中文化',
  };

  static ProcessMode parse(String? raw) => switch (raw) {
    'dubMerge' => ProcessMode.dubMerge,
    'jpMerge' => ProcessMode.jpMerge,
    'styleConvert' => ProcessMode.styleConvert,
    'chineseConvert' => ProcessMode.chineseConvert,
    _ => ProcessMode.merge,
  };

  static String encode(ProcessMode mode) => mode.name;
}
