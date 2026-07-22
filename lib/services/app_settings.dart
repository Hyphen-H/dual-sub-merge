import 'package:shared_preferences/shared_preferences.dart';

import '../models/merge_options.dart';

class AppSettings {
  static const _kResX = 'playResX';
  static const _kResY = 'playResY';
  static const _kRemoveCredits = 'removeCredits';
  static const _kExtract = 'extractFromVideo';
  static const _kExtractDir = 'extractSubdir';
  static const _kOverwrite = 'overwrite';
  static const _kDragAutoRun = 'dragAutoRun';
  static const _kTagLanguage = 'tagLanguageOnMerge';
  static const _kOutputDirMode = 'outputDirMode';
  static const _kCustomOutputDir = 'customOutputDir';
  static const _kMkvDir = 'mkvToolNixDir';
  static const _kFfmpeg = 'ffmpegPath';
  static const _kFfprobe = 'ffprobePath';
  static const _kBlacklist = 'blacklistRules';
  static const _kStyles = 'styleLines';
  static const _kLastDir = 'lastDir';

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
      extractFromVideo: p.getBool(_kExtract) ?? true,
      extractSubdir: p.getString(_kExtractDir) ?? 'dual-sub-merge-extract',
      overwrite: p.getBool(_kOverwrite) ?? true,
      dragAutoRun: p.getBool(_kDragAutoRun) ?? false,
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
    await p.setBool(_kExtract, o.extractFromVideo);
    await p.setString(_kExtractDir, o.extractSubdir);
    await p.setBool(_kOverwrite, o.overwrite);
    await p.setBool(_kDragAutoRun, o.dragAutoRun);
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
}
