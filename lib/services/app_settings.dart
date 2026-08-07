import 'package:shared_preferences/shared_preferences.dart';

import '../models/merge_options.dart';
import 'ui_font.dart';

class AppSettings {
  static const _kResX = 'playResX';
  static const _kResY = 'playResY';
  static const _kRemoveCredits = 'removeCredits';
  static const _kExtractDir = 'extractSubdir';
  static const _kOverwrite = 'overwrite';
  static const _kTagLanguage = 'tagLanguageOnMerge';
  static const _kOutputDirMode = 'outputDirMode';
  static const _kCustomOutputDir = 'customOutputDir';
  static const _kMkvDir = 'mkvToolNixDir';
  static const _kFfmpeg = 'ffmpegPath';
  static const _kFfprobe = 'ffprobePath';
  static const _kBlacklist = 'blacklistRules';
  static const _kStyles = 'styleLines';
  static const _kLastDir = 'lastDir';
  static const _kLastSubtitleFiles = 'lastSubtitleFiles';
  static const _kLastVideoDir = 'lastVideoDir';
  static const _kLastVideoFiles = 'lastVideoFiles';
  static const _kUiFontFamily = 'uiFontFamily';
  static const _kUiFontFile = 'uiFontFilePath';

  static OutputDirMode _parseOutputMode(String? raw) {
    return switch (raw) {
      'source' => OutputDirMode.source,
      'custom' => OutputDirMode.custom,
      _ => OutputDirMode.mergedSubdir,
    };
  }

  static String _encodeOutputMode(OutputDirMode m) {
    return switch (m) {
      OutputDirMode.source => 'source',
      OutputDirMode.mergedSubdir => 'mergedSubdir',
      OutputDirMode.custom => 'custom',
    };
  }

  static Future<MergeOptions> loadOptions() async {
    final p = await SharedPreferences.getInstance();
    final opts = MergeOptions(
      playResX: p.getInt(_kResX) ?? 1920,
      playResY: p.getInt(_kResY) ?? 1080,
      removeCredits: p.getBool(_kRemoveCredits) ?? true,
      extractSubdir: p.getString(_kExtractDir) ?? 'dual-sub-merge-extract',
      overwrite: p.getBool(_kOverwrite) ?? true,
      tagLanguageOnMerge: p.getBool(_kTagLanguage) ?? false,
      outputDirMode: _parseOutputMode(p.getString(_kOutputDirMode)),
      customOutputDir: p.getString(_kCustomOutputDir) ?? '',
      mkvToolNixDir: p.getString(_kMkvDir) ?? '',
      ffmpegPath: p.getString(_kFfmpeg) ?? '',
      ffprobePath: p.getString(_kFfprobe) ?? '',
      blacklistRules: p.getStringList(_kBlacklist),
      styleLines: p.getStringList(_kStyles),
    );
    return opts;
  }

  static Future<void> saveOptions(MergeOptions o) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kResX, o.playResX);
    await p.setInt(_kResY, o.playResY);
    await p.setBool(_kRemoveCredits, o.removeCredits);
    await p.setString(_kExtractDir, o.extractSubdir);
    await p.setBool(_kOverwrite, o.overwrite);
    await p.setBool(_kTagLanguage, o.tagLanguageOnMerge);
    await p.setString(_kOutputDirMode, _encodeOutputMode(o.outputDirMode));
    await p.setString(_kCustomOutputDir, o.customOutputDir);
    await p.setString(_kMkvDir, o.mkvToolNixDir);
    await p.setString(_kFfmpeg, o.ffmpegPath);
    await p.setString(_kFfprobe, o.ffprobePath);
    await p.setStringList(_kBlacklist, o.blacklistRules);
    await p.setStringList(_kStyles, o.styleLines);
  }

  static Future<String?> loadLastDir() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastDir);
  }

  static Future<void> saveLastDir(String dir) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastDir, dir);
  }

  static Future<List<String>> loadLastSubtitleFiles() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kLastSubtitleFiles) ?? const [];
  }

  static Future<void> saveLastSubtitleFiles(Iterable<String> paths) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLastSubtitleFiles, paths.toList());
  }

  static Future<String?> loadLastVideoDir() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastVideoDir);
  }

  static Future<void> saveLastVideoDir(String dir) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastVideoDir, dir);
  }

  static Future<List<String>> loadLastVideoFiles() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kLastVideoFiles) ?? const [];
  }

  static Future<void> saveLastVideoFiles(Iterable<String> paths) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLastVideoFiles, paths.toList());
  }

  static Future<UiFontSettings> loadUiFont() async {
    final p = await SharedPreferences.getInstance();
    return UiFontSettings(
      family: p.getString(_kUiFontFamily) ?? '',
      filePath: p.getString(_kUiFontFile) ?? '',
    );
  }

  static Future<void> saveUiFont(UiFontSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUiFontFamily, s.family);
    await p.setString(_kUiFontFile, s.filePath);
  }
}
