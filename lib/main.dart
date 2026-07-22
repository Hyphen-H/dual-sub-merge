import 'package:flutter/material.dart';

import 'services/app_settings.dart';
import 'services/ui_font.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DualSubMergeApp());
}

class DualSubMergeApp extends StatefulWidget {
  const DualSubMergeApp({super.key});

  static DualSubMergeAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<DualSubMergeAppState>();
  }

  @override
  State<DualSubMergeApp> createState() => DualSubMergeAppState();
}

class DualSubMergeAppState extends State<DualSubMergeApp> {
  ThemeData _theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    useMaterial3: true,
  );
  UiFontSettings _font = const UiFontSettings();
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final font = await AppSettings.loadUiFont();
    await applyUiFont(font);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> applyUiFont(UiFontSettings font) async {
    final family = await UiFontLoader.apply(font);
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0));
    if (!mounted) return;
    setState(() {
      _font = font;
      _theme = UiFontLoader.buildTheme(scheme, family);
    });
  }

  UiFontSettings get uiFont => _font;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dual-sub-merge',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: _ready
          ? const HomePage()
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
