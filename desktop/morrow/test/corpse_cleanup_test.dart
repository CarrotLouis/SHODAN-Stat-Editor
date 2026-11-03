import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodan_desktop/backend.dart';
import 'package:shodan_desktop/diagnostics.dart';
import 'package:shodan_desktop/main.dart';

class CorpseBackend extends Backend {
  CorpseBackend() : super(diagnostics: AppDiagnostics(persist: false));
  final calls = <String>[];
  int installs = 0;
  bool supported = true, changed = false, failSave = false;
  String mode = 'original', fragments = 'original';
  Map<String, dynamic> snapshot() => {
    'supported': supported,
    'mode': mode,
    'fragments': fragments,
    'changed': changed,
    if (!supported) 'problem': '当前数据版本不匹配，未修改',
  };
  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {}
  @override
  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    calls.add('$method:$args');
    switch (method) {
      case 'items':
        return [];
      case 'corpse_status':
        return snapshot();
      case 'corpse_set':
        if (failSave) throw StateError('配置保存失败');
        mode = args[0] as String;
        fragments = args[1] == true
            ? 'fast'
            : args[1] == 'custom'
            ? 'custom'
            : 'original';
        changed = mode != 'original' || fragments != 'original';
        return snapshot();
      case 'corpse_reset':
        mode = 'original';
        fragments = 'original';
        changed = false;
        return snapshot();
      case 'install_preview':
        return {
          'entries': [
            {
              'equipment': '尸体清理',
              'parameter': '尸体消退策略',
              'before': '原版',
              'after': '约 6 秒',
            },
            {
              'equipment': '尸体清理',
              'parameter': '碎块寿命',
              'before': '原版',
              'after': '2 秒',
            },
          ],
          'files': ['generated_entities.dl_bin'],
          'warnings': [],
          'problems': [],
        };
      case 'install_task':
        installs++;
        return {'ok': true, 'message': '已写入游戏'};
    }
    return {};
  }
}

Future<void> openCorpses(WidgetTester tester, CorpseBackend backend) async {
  await tester.binding.setSurfaceSize(const Size(1480, 960));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('corpse-preview-root'),
      child: Workbench(backend: backend, persistAppearance: false),
    ),
  );
  await tester.pumpAndSettle();
  final enemy = find.byKey(const ValueKey('navigation-Terminids'));
  final corpses = find.byKey(const ValueKey('navigation-Corpses'));
  final records = find.byKey(const ValueKey('navigation-Records'));
  expect(tester.getTopLeft(enemy).dy, lessThan(tester.getTopLeft(corpses).dy));
  expect(
    tester.getTopLeft(corpses).dy,
    lessThan(tester.getTopLeft(records).dy),
  );
  await tester.tap(corpses);
  await tester.pumpAndSettle();
}

void main() {
  const preview = String.fromEnvironment('SHODAN_CORPSE_PREVIEW');
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('尸体清理位于敌人后面，配置经全局预览确认后统一写入', (tester) async {
    final backend = CorpseBackend();
    await openCorpses(tester, backend);
    expect(find.text('清理尸体与碎块'), findsOneWidget);
    expect(backend.calls.any((s) => s.startsWith('items:[Corpses')), isFalse);
    await tester.tap(find.byKey(const ValueKey('corpse-combined')));
    await tester.pumpAndSettle();
    expect(backend.mode, 'fast');
    expect(backend.fragments, 'fast');
    expect(backend.installs, 0);
    await tester.tap(find.text('写入游戏'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尸体消退策略'), findsOneWidget);
    expect(find.text('尸体清理 · 碎块寿命'), findsOneWidget);
    expect(backend.installs, 0);
    await tester.tap(find.text('确认写入'));
    // The workbench stays busy until the result dialog is dismissed. Its
    // background progress indicator deliberately keeps scheduling frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(backend.installs, 1);
    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('模式和碎块可独立切换，恢复通过同一配置接口', (tester) async {
    final backend = CorpseBackend();
    await openCorpses(tester, backend);
    await tester.tap(find.text('套用小型单位补丁'));
    await tester.pumpAndSettle();
    expect(backend.mode, 'instant');
    expect(backend.fragments, 'fast');
    await tester.tap(find.byKey(const ValueKey('corpse-fragments')));
    await tester.pumpAndSettle();
    expect(backend.mode, 'instant');
    expect(backend.fragments, 'original');
    await tester.tap(find.byKey(const ValueKey('corpse-reset')));
    await tester.pumpAndSettle();
    expect(backend.mode, 'original');
    expect(backend.fragments, 'original');
    expect(backend.installs, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('不支持的数据版本禁用清理控件', (tester) async {
    final backend = CorpseBackend()..supported = false;
    await openCorpses(tester, backend);
    expect(find.textContaining('当前数据版本不匹配'), findsOneWidget);
    final combined = tester.widget<FilledButton>(
      find.byKey(const ValueKey('corpse-combined')),
    );
    expect(combined.onPressed, isNull);
    expect(backend.installs, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  if (preview.isNotEmpty) {
    testWidgets('导出尸体清理页面预览', (tester) async {
      await tester.runAsync(() async {
        final text = FontLoader('MiSans')
          ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.subset.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await text.load();
        await icons.load();
      });
      await openCorpses(tester, CorpseBackend());
      await tester.tap(find.byKey(const ValueKey('corpse-combined')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('corpse-preview-root')),
        matchesGoldenFile(Uri.file(preview)),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
  }
}
