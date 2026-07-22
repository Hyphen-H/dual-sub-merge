import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UiFontSettings {
  const UiFontSettings({
    this.family = '',
    this.filePath = '',
  });

  /// System font family name; empty = Material default.
  final String family;

  /// Optional ttf/otf path; when set and loadable, overrides [family].
  final String filePath;

  static const loadedFamilyName = 'AppUiCustomFont';

  static const presets = <(String label, String family)>[
    ('默认', ''),
    ('微软雅黑', 'Microsoft YaHei'),
    ('微软雅黑 UI', 'Microsoft YaHei UI'),
    ('宋体', 'SimSun'),
    ('黑体', 'SimHei'),
    ('等线', 'DengXian'),
    ('楷体', 'KaiTi'),
    ('Segoe UI', 'Segoe UI'),
  ];

  UiFontSettings copyWith({String? family, String? filePath}) {
    return UiFontSettings(
      family: family ?? this.family,
      filePath: filePath ?? this.filePath,
    );
  }
}

class UiFontLoader {
  static String? _activeFamily;

  static String? get activeFamily => _activeFamily;

  /// Loads custom file font if needed. Returns fontFamily for ThemeData (null = default).
  static Future<String?> apply(UiFontSettings s) async {
    final path = s.filePath.trim();
    if (path.isNotEmpty) {
      final f = File(path);
      if (f.existsSync()) {
        try {
          final bytes = await f.readAsBytes();
          final loader = FontLoader(UiFontSettings.loadedFamilyName)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
          _activeFamily = UiFontSettings.loadedFamilyName;
          return _activeFamily;
        } catch (_) {
          _activeFamily = null;
          return s.family.trim().isEmpty ? null : s.family.trim();
        }
      }
    }
    final fam = s.family.trim();
    _activeFamily = fam.isEmpty ? null : fam;
    return _activeFamily;
  }

  static ThemeData buildTheme(ColorScheme scheme, String? fontFamily) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    // Keep a single regular weight for body UI text.
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamily: fontFamily,
    );
    return base.copyWith(
      textTheme: text.copyWith(
        bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
        bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
        bodySmall: text.bodySmall?.copyWith(fontWeight: FontWeight.w400),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w400),
        labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w400),
        labelSmall: text.labelSmall?.copyWith(fontWeight: FontWeight.w400),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w400),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w400),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w400),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
