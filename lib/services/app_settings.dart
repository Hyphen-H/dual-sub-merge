import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_workspace.dart';
import '../models/ass_style.dart';
import '../models/extract_pair_mode.dart';
import '../models/merge_options.dart';
import '../models/process_mode.dart';
import 'ui_font.dart';

class AppSettings {
  static const _kResX = 'playResX';
  static const _kResY = 'playResY';
  static const _kStyleBaseResY = 'styleBaseResY';
  static const _kRemoveCredits = 'removeCredits';
  static const _kExtractDir = 'extractSubdir';
  static const _kOverwrite = 'overwrite';
  static const _kTagLanguage = 'tagLanguageOnMerge';
  static const _kHdrSubtitle = 'hdrSubtitle';
  static const _kOutputDirMode = 'outputDirMode';
  static const _kWorkspace = 'workspace';
  static const _kProcessMode = 'processMode';
  static const _kExtractPairMode = 'extractPairMode';
  static const _kMkvDir = 'mkvToolNixDir';
  static const _kFfmpeg = 'ffmpegPath';
  static const _kFfprobe = 'ffprobePath';
  static const _kBlacklist = 'blacklistRules';
  static const _kStyles = 'styleLines';
  static const _kLastDir = 'lastDir';
  static const _kLastSubtitleFiles = 'lastSubtitleFiles';
  static const _kUiFontFamily = 'uiFontFamily';
  static const _kUiFontFile = 'uiFontFilePath';

  static OutputDirMode _parseOutputMode(String? raw) {
    return switch (raw) {
      'source' => OutputDirMode.source,
      // 'custom' and anything unknown fall back to the default subdirectory.
      _ => OutputDirMode.mergedSubdir,
    };
  }

  static String _encodeOutputMode(OutputDirMode m) {
    return switch (m) {
      OutputDirMode.source => 'source',
      OutputDirMode.mergedSubdir => 'mergedSubdir',
    };
  }

  static Future<MergeOptions> loadOptions() async {
    final p = await SharedPreferences.getInstance();
    var styleLines = p.getStringList(_kStyles);
    var styleBaseResY = p.getInt(_kStyleBaseResY) ?? 1080;
    // Migrate the pre-dimmed built-ins and the earlier JP preset so an upgrade
    // does not look like a user customization.
    if (styleLines != null && StyleCatalog.isLegacyBuiltInStyles(styleLines)) {
      styleLines = null;
    } else if (styleLines != null &&
        StyleCatalog.isLegacyJpReferenceStyles(styleLines)) {
      styleLines = StyleCatalog.jpReferenceStyleLines;
      if (styleBaseResY == StyleCatalog.defaultBaseResY) {
        styleBaseResY = StyleCatalog.jpReferenceBaseResY;
      }
    }
    final rawProcessMode = p.getString(_kProcessMode);
    final workspace = rawProcessMode == 'extract'
        ? AppWorkspace.extract
        : AppWorkspaceInfo.parse(p.getString(_kWorkspace));
    final opts = MergeOptions(
      playResX: p.getInt(_kResX) ?? 1920,
      playResY: p.getInt(_kResY) ?? 1080,
      styleBaseResY: styleBaseResY,
      removeCredits: p.getBool(_kRemoveCredits) ?? true,
      extractSubdir: p.getString(_kExtractDir) ?? 'dual-sub-merge-extract',
      overwrite: p.getBool(_kOverwrite) ?? true,
      tagLanguageOnMerge: p.getBool(_kTagLanguage) ?? false,
      hdrSubtitle: p.getBool(_kHdrSubtitle) ?? true,
      outputDirMode: _parseOutputMode(p.getString(_kOutputDirMode)),
      workspace: workspace,
      processMode: ProcessModeInfo.parse(rawProcessMode),
      extractPairMode: ExtractPairModeInfo.parse(
        p.getString(_kExtractPairMode),
      ),
      mkvToolNixDir: p.getString(_kMkvDir) ?? '',
      ffmpegPath: p.getString(_kFfmpeg) ?? '',
      ffprobePath: p.getString(_kFfprobe) ?? '',
      blacklistRules: p.getStringList(_kBlacklist),
      styleLines: styleLines,
    );
    return opts;
  }

  static Future<void> saveOptions(MergeOptions o) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kResX, o.playResX);
    await p.setInt(_kResY, o.playResY);
    await p.setInt(_kStyleBaseResY, o.styleBaseResY);
    await p.setBool(_kRemoveCredits, o.removeCredits);
    await p.setString(_kExtractDir, o.extractSubdir);
    await p.setBool(_kOverwrite, o.overwrite);
    await p.setBool(_kTagLanguage, o.tagLanguageOnMerge);
    await p.setBool(_kHdrSubtitle, o.hdrSubtitle);
    await p.setString(_kOutputDirMode, _encodeOutputMode(o.outputDirMode));
    await p.setString(_kWorkspace, AppWorkspaceInfo.encode(o.workspace));
    await p.setString(_kProcessMode, ProcessModeInfo.encode(o.processMode));
    await p.setString(
      _kExtractPairMode,
      ExtractPairModeInfo.encode(o.extractPairMode),
    );
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

  static Future<List<String>> loadLastInputFiles() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kLastSubtitleFiles) ?? const [];
  }

  static Future<void> saveLastInputFiles(Iterable<String> paths) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLastSubtitleFiles, paths.toList());
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
