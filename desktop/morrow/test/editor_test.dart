import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shodan_desktop/backend.dart';
import 'package:shodan_desktop/main.dart';
import 'package:shodan_desktop/glass_theme.dart';
import 'package:shodan_desktop/diagnostics.dart';

class FakeBackend extends Backend {
  FakeBackend() : super(diagnostics: AppDiagnostics(persist: false));
  String value = '66';
  int installs = 0;
  @override
  Future<void> start() async {}
  @override
  Future<void> close() async {}
  @override
  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    switch (method) {
      case 'game_text':
        return {'available': false};
      case 'editor_mode':
        return false;
      case 'items':
        return [
          {'id': 'test', 'name': 'AR-11 仲裁者', 'changed': false},
        ];
      case 'select':
        return true;
      case 'rows':
        return [
          {
            'id': 1,
            'label': '伤害',
            'section': '伤害参数',
            'value': int.parse(value),
            'text': value,
            'default_text': '66',
            'help': ['功能提示'],
            'flag': false,
            'choice': false,
            'changed': value != '66',
          },
        ];
      case 'set':
        value = args[1];
        return true;
      case 'reset':
        value = '66';
        return true;
      case 'install_preview':
        return {
          'entries': [],
          'warnings': [],
          'problems': ['测试阻止写入'],
        };
      case 'install':
        installs++;
        return 'written';
    }
    return {};
  }
}

class ScrollingBackend extends FakeBackend {
  @override
  Future<dynamic> call(String method, [List<dynamic> args = const []]) async {
    if (method == 'game_text')
      return {'available': true, 'value': '测试', 'original': '原文'};
    if (method == 'rows')
      return List.generate(
        36,
        (i) => {
          'id': i + 1,
          'label': '测试参数 $i',
          'section': '分类 $i',
          'value': 1,
          'text': '1',
          'default_text': '1',
        },
      );
    return super.call(method, args);
  }
}

void main() {
  testWidgets('分类四列且反复滚动不污染文字展开状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1480, 960));
    await tester.pumpWidget(
      Workbench(backend: ScrollingBackend(), persistAppearance: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final scroll = find.byKey(
      const PageStorageKey('parameter-categories:test'),
    );
    expect(scroll, findsOneWidget);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid).last);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    for (var i = 0; i < 3; i++) {
      await tester.drag(scroll, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, 1400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('侧边栏仅保留主分类，子分类仍可访问', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(
      Workbench(backend: FakeBackend(), persistAppearance: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(9));
    expect(find.widgetWithText(ChoiceChip, '配件'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '配件'));
    await tester.pumpAndSettle();
    final equipment = tester.widget<ListTile>(
      find.byKey(const ValueKey('navigation-Primary')),
    );
    expect(equipment.selected, isTrue);
    await tester.tap(find.byKey(const ValueKey('navigation-Terminids')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '机器人'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '敌人生成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('参数保存恢复与写入拦截', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1480, 960));
    final backend = FakeBackend();
    await tester.pumpWidget(
      MaterialApp(home: Workbench(backend: backend, persistAppearance: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('AR-11 仲裁者'), findsOneWidget);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDialog), findsOneWidget);
    final input = find.byType(TextField).last;
    await tester.enterText(input, '123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(backend.value, '123');
    await tester.tap(find.byTooltip('恢复原值'));
    await tester.pumpAndSettle();
    expect(backend.value, '66');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写入游戏'));
    await tester.pumpAndSettle();
    expect(find.textContaining('测试阻止写入'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认写入'),
    );
    expect(confirm.onPressed, isNull);
    expect(backend.installs, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('字号滑条影响显式字号的标题和弹窗', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1480, 960));
    await tester.pumpWidget(
      Workbench(backend: FakeBackend(), persistAppearance: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('navigation-Settings')));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider).at(1));
    // The first slider controls background dim; the second controls font size.
    slider.onChanged!(20);
    slider.onChangeEnd!(20);
    await tester.pumpAndSettle();
    final title = tester.element(find.text('外观与阅读'));
    expect(
      MediaQuery.textScalerOf(title).scale(22),
      closeTo(22 * 20 / 14, .001),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
