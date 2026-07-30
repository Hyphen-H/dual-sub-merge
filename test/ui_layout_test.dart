import 'package:dual_sub_merge/services/ui_font.dart';
import 'package:dual_sub_merge/ui/blacklist_page.dart';
import 'package:dual_sub_merge/ui/design_system.dart';
import 'package:dual_sub_merge/ui/home_page.dart';
import 'package:dual_sub_merge/ui/settings_page.dart';
import 'package:dual_sub_merge/ui/styles_page.dart';
import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData _theme() => UiFontLoader.buildTheme(
  ColorScheme.fromSeed(seedColor: const Color(0xFF315FBA)),
  null,
);

Future<void> _pumpAt(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: _theme(), home: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home workspace lays out at desktop size', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));
    expect(find.text('字幕处理'), findsWidgets);
    expect(find.text('开始合并'), findsOneWidget);
  });

  testWidgets('home workspace adapts to compact desktop size', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1024, 640));
    expect(find.byIcon(Icons.subtitles_outlined), findsOneWidget);
    expect(find.text('任务列表'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.movie_outlined).first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('开始抽轨'), findsOneWidget);
    final exception = tester.takeException();
    if (exception is FlutterError) {
      // ignore: avoid_print
      print(exception.toStringDeep());
      debugDumpRenderTree();
    }
    expect(exception, isNull);
  });

  testWidgets('sidebar uses no Material ink and switches pages', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    Finder nav(String label) => find.widgetWithText(SidebarNavItem, label);

    expect(
      find.descendant(of: nav('字幕处理'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(of: nav('字幕处理'), matching: find.byType(Material)),
      findsNothing,
    );
    expect(find.text('开始合并'), findsOneWidget);

    await tester.tap(nav('视频处理'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('开始抽轨'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('option chips keep their own icons when selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'removeCredits': true,
      'tagLanguageOnMerge': true,
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    final removeCredits = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '删除致谢'),
    );
    final rename = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '标记语言改名'),
    );
    expect(removeCredits.showCheckmark, isFalse);
    expect(rename.showCheckmark, isFalse);
  });

  testWidgets('long input folder path is not ellipsized', (tester) async {
    const longPath =
        r'C:\Media Library\A Very Long Collection Name\Season 01\Episode Sources\Original Video And Subtitle Assets';
    SharedPreferences.setMockInitialValues({'lastDir': longPath});
    await _pumpAt(tester, const HomePage(), const Size(1024, 640));

    final pathTexts = tester.widgetList<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.contains('Original Video And Subtitle Assets') ??
                false),
      ),
    );
    expect(pathTexts, isNotEmpty);
    expect(
      pathTexts.any((text) => text.maxLines == null && text.overflow == null),
      isTrue,
    );
  });

  testWidgets('secondary pages lay out at compact desktop size', (
    tester,
  ) async {
    final options = MergeOptions();
    final pages = <Widget>[
      SettingsPage(options: options, onChanged: (_) {}),
      StylesPage(options: options, onChanged: (_) {}),
      BlacklistPage(options: options, onChanged: (_) {}),
    ];
    for (final page in pages) {
      await _pumpAt(tester, page, const Size(1024, 640));
    }
  });
}
