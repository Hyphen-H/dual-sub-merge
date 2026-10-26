import 'package:dual_sub_merge/services/ui_font.dart';
import 'package:dual_sub_merge/ui/blacklist_page.dart';
import 'package:dual_sub_merge/ui/design_system.dart';
import 'package:dual_sub_merge/ui/home_page.dart';
import 'package:dual_sub_merge/ui/settings_page.dart';
import 'package:dual_sub_merge/ui/styles_page.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dual_sub_merge/models/extract_pair_mode.dart';
import 'package:dual_sub_merge/models/merge_options.dart';
import 'package:dual_sub_merge/models/process_mode.dart';
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
    expect(find.text('视频抽轨'), findsOneWidget);
    expect(find.text('开始中英配对'), findsOneWidget);
    expect(find.text('视频处理'), findsNothing);
  });

  testWidgets('sidebar switches between subtitle and extract workspaces', (
    tester,
  ) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));
    expect(find.text('任务列表'), findsOneWidget);
    expect(find.text('开始中英配对'), findsOneWidget);

    await tester.tap(find.widgetWithText(SidebarNavItem, '视频抽轨'));
    await tester.pumpAndSettle();

    expect(find.text('开始抽轨'), findsOneWidget);
    expect(find.text('开始中英配对'), findsNothing);
    expect(find.byType(ExtractPairModePicker), findsOneWidget);
    // Subtitle-only controls are hidden while extracting.
    expect(find.widgetWithText(OptionCheck, 'HDR'), findsNothing);
    expect(find.byType(SegmentedButton<OutputDirMode>), findsNothing);

    await tester.tap(find.widgetWithText(SidebarNavItem, '字幕处理'));
    await tester.pumpAndSettle();

    expect(find.text('开始中英配对'), findsOneWidget);
    expect(find.byType(ExtractPairModePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar uses no Material ink', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    Finder nav(String label) => find.widgetWithText(SidebarNavItem, label);

    for (final label in ['字幕处理', '视频抽轨', '字幕样式', '致谢黑名单', '设置']) {
      expect(
        find.descendant(of: nav(label), matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: nav(label), matching: find.byType(Material)),
        findsNothing,
      );
    }
    expect(find.text('开始中英配对'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('option toggles are square checkboxes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'removeCredits': true,
      'tagLanguageOnMerge': true,
      'hdrSubtitle': true,
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    OptionCheck check(String label) =>
        tester.widget<OptionCheck>(find.widgetWithText(OptionCheck, label));

    expect(check('删除致谢').value, isTrue);
    expect(check('标记语言改名').value, isTrue);
    expect(check('HDR').value, isTrue);
    expect(check(r'\an8 转上方注释').value, isFalse);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(OptionCheck, 'HDR'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pumpAndSettle();
    expect(check('HDR').value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an8 annotation choice is restored from settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'an8AsAnnotation': true});
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(
      tester
          .widget<OptionCheck>(find.widgetWithText(OptionCheck, r'\an8 转上方注释'))
          .value,
      isTrue,
    );
  });

  testWidgets('HDR choice is restored from settings', (tester) async {
    SharedPreferences.setMockInitialValues({'hdrSubtitle': false});
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(
      tester.widget<OptionCheck>(find.widgetWithText(OptionCheck, 'HDR')).value,
      isFalse,
    );
  });

  testWidgets('pairing modes support single and multiple selection', (
    tester,
  ) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    final picker = find.byType(ProcessModePicker);
    expect(picker, findsOneWidget);
    expect(tester.widget<ProcessModePicker>(picker).mode, ProcessMode.merge);
    expect(find.text('开始中英配对'), findsOneWidget);
    expect(find.textContaining('中外单语字幕按文件名前缀配对'), findsNothing);
    final segment = tester.widget<SegmentedButton<ProcessMode>>(
      find.byType(SegmentedButton<ProcessMode>).first,
    );
    final scheme = Theme.of(
      tester.element(find.byType(SegmentedButton<ProcessMode>).first),
    ).colorScheme;
    expect(
      segment.style?.backgroundColor?.resolve({WidgetState.selected}),
      scheme.primary,
    );
    expect(
      segment.style?.foregroundColor?.resolve({WidgetState.selected}),
      scheme.onPrimary,
    );

    await tester.tap(find.text('中英配'));
    await tester.pumpAndSettle();

    expect(tester.widget<ProcessModePicker>(picker).mode, ProcessMode.merge);
    expect(tester.widget<ProcessModePicker>(picker).selectedPairModes, {
      ProcessMode.merge,
      ProcessMode.dubMerge,
    });
    expect(find.text('开始批量配对'), findsOneWidget);

    await tester.tap(find.text('中英配'));
    await tester.pumpAndSettle();
    expect(tester.widget<ProcessModePicker>(picker).selectedPairModes, {
      ProcessMode.merge,
    });

    await tester.tap(find.text('中英配对'));
    await tester.pumpAndSettle();
    expect(tester.widget<ProcessModePicker>(picker).selectedPairModes, isEmpty);
    expect(find.text('请选择配对模式'), findsOneWidget);

    await tester.tap(find.text('中英配对'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('中文转换'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ProcessModePicker>(picker).mode,
      ProcessMode.chineseConvert,
    );
    expect(find.text('开始中文化'), findsOneWidget);
    expect(find.text('开始中英配对'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('process mode is restored from settings', (tester) async {
    SharedPreferences.setMockInitialValues({'processMode': 'chineseConvert'});
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(find.text('中文转换'), findsOneWidget);
    expect(find.text('开始中文化'), findsOneWidget);
  });

  testWidgets('multiple subtitle pairing modes are restored', (tester) async {
    SharedPreferences.setMockInitialValues({
      'processMode': 'merge',
      'selectedPairModes': ['merge', 'jpMerge'],
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    final picker = tester.widget<ProcessModePicker>(
      find.byType(ProcessModePicker),
    );
    expect(picker.selectedPairModes, {ProcessMode.merge, ProcessMode.jpMerge});
    expect(find.text('开始批量配对'), findsOneWidget);
  });

  testWidgets('extract workspace and pair mode are restored', (tester) async {
    SharedPreferences.setMockInitialValues({
      'workspace': 'extract',
      'extractPairMode': 'chsJpn',
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(find.text('开始抽轨'), findsOneWidget);
    final picker = tester.widget<ExtractPairModePicker>(
      find.byType(ExtractPairModePicker),
    );
    expect(picker.mode, ExtractPairMode.chsJpn);
  });

  testWidgets('extract Dubtitle pair mode is restored', (tester) async {
    SharedPreferences.setMockInitialValues({
      'workspace': 'extract',
      'extractPairMode': 'chsEngDub',
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    final picker = tester.widget<ExtractPairModePicker>(
      find.byType(ExtractPairModePicker),
    );
    expect(picker.mode, ExtractPairMode.chsEngDub);
    expect(find.text('中英配'), findsOneWidget);
  });

  testWidgets('multiple extract pair modes are restored', (tester) async {
    SharedPreferences.setMockInitialValues({
      'workspace': 'extract',
      'extractPairMode': 'chsEng',
      'selectedExtractPairModes': ['chsEng', 'chsJpn'],
    });
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    final picker = tester.widget<ExtractPairModePicker>(
      find.byType(ExtractPairModePicker),
    );
    expect(picker.selectedModes, {
      ExtractPairMode.chsEng,
      ExtractPairMode.chsJpn,
    });
  });

  testWidgets('legacy extract process mode opens the extract workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'processMode': 'extract'});
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(find.text('开始抽轨'), findsOneWidget);
    expect(find.byType(ExtractPairModePicker), findsOneWidget);
  });

  testWidgets('input offers direct file and folder buttons', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    // No first-level chooser any more: both entries sit on the input card.
    expect(find.widgetWithText(OutlinedButton, '文件'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '文件夹'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '选择'), findsNothing);
    expect(find.text('选择字幕文件'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one input card and one window-wide drop target', (tester) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(find.text('输入来源'), findsOneWidget);
    expect(find.text('输出位置'), findsNothing);
    // The whole window accepts drops, so there is exactly one DropTarget.
    expect(find.byType(DropTarget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('output directory is limited to Subtitles and source', (
    tester,
  ) async {
    await _pumpAt(tester, const HomePage(), const Size(1280, 720));

    expect(find.text('./${MergeOptions.mergedSubdirName}'), findsOneWidget);
    expect(find.text('./'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('input folder cache is ignored on app launch', (tester) async {
    const longPath =
        r'C:\Media Library\A Very Long Collection Name\Season 01\Episode Sources\Original Video And Subtitle Assets';
    SharedPreferences.setMockInitialValues({'lastDir': longPath});
    await _pumpAt(tester, const HomePage(), const Size(1024, 640));

    expect(
      find.textContaining('Original Video And Subtitle Assets'),
      findsNothing,
    );
    expect(find.text('未选择输入'), findsOneWidget);
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
