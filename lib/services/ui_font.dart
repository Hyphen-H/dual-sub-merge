import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UiFontSettings {
  const UiFontSettings({this.family = '', this.filePath = ''});

  final String family;
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

  static ThemeData buildTheme(ColorScheme _, String? fontFamily) {
    const primary = Color(0xFF315FBA);
    const surface = Color(0xFFFFFFFF);
    const canvas = Color(0xFFF5F7FA);
    const ink = Color(0xFF18202F);
    const muted = Color(0xFF657083);
    const outline = Color(0xFFDDE2EA);
    const scheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE8EEFC),
      onPrimaryContainer: Color(0xFF244984),
      secondary: Color(0xFF56647A),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEDF0F5),
      onSecondaryContainer: Color(0xFF364153),
      error: Color(0xFFC23B45),
      onError: Colors.white,
      errorContainer: Color(0xFFFDECEE),
      onErrorContainer: Color(0xFF8A2730),
      surface: surface,
      onSurface: ink,
      surfaceContainerLowest: surface,
      surfaceContainerLow: Color(0xFFFAFBFC),
      surfaceContainer: Color(0xFFF5F7FA),
      surfaceContainerHigh: Color(0xFFF0F3F7),
      surfaceContainerHighest: Color(0xFFE9EDF3),
      onSurfaceVariant: muted,
      outline: Color(0xFFB8C0CD),
      outlineVariant: outline,
      shadow: Color(0x1A18202F),
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: fontFamily,
    );
    final regularText = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w400,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w400),
      bodyLarge: text.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w400),
      labelSmall: text.labelSmall?.copyWith(fontWeight: FontWeight.w400),
    );

    const rounded8 = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    return base.copyWith(
      textTheme: regularText,
      splashFactory: InkRipple.splashFactory,
      splashColor: primary.withValues(alpha: 0.08),
      highlightColor: primary.withValues(alpha: 0.04),
      hoverColor: primary.withValues(alpha: 0.04),
      focusColor: primary.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: regularText.titleLarge,
        toolbarHeight: 68,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: rounded8,
          textStyle: regularText.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          foregroundColor: ink,
          side: const BorderSide(color: outline),
          shape: rounded8,
          textStyle: regularText.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: rounded8,
          textStyle: regularText.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          shape: rounded8,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFC23B45)),
        ),
        labelStyle: regularText.bodyMedium?.copyWith(color: muted),
        hintStyle: regularText.bodyMedium?.copyWith(
          color: const Color(0xFF9099A8),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: Color(0xFF9CA6B5)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: const Color(0xFFE8EEFC),
        disabledColor: const Color(0xFFF0F2F5),
        side: const BorderSide(color: outline),
        shape: rounded8,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: regularText.bodyMedium,
        secondaryLabelStyle: regularText.bodyMedium?.copyWith(
          color: const Color(0xFF244984),
        ),
        showCheckmark: true,
        checkmarkColor: primary,
      ),
      dialogTheme: DialogThemeData(
        elevation: 18,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: regularText.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: regularText.bodyMedium?.copyWith(color: Colors.white),
        shape: rounded8,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: const Color(0xFF242C39),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: regularText.bodySmall?.copyWith(color: Colors.white),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: base.inputDecorationTheme,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}
