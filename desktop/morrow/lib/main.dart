import 'glass_theme.dart';
import 'install_dialog.dart';
import 'diagnostics_ui.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'number_display.dart';
import 'preference_slider.dart';
import 'package:flutter/material.dart';
import 'backend.dart';
import 'desktop_frame.dart';
import 'armor_page.dart';
import 'armor_item.dart';
import 'game_text.dart';
import 'preset_page.dart';
import 'review_body.dart';
import 'corpse_cleanup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDesktopFrame();
  runApp(const Workbench());
}

class Workbench extends StatefulWidget {
  const Workbench({super.key, this.backend, this.persistAppearance = true});
  final bool persistAppearance;
  final Backend? backend;
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  late final Backend backend = widget.backend ?? Backend();
  bool ready = false, busy = false, dark = true;
  bool diagnosing = false;
  String diagnosticResult = '';
  String status = '正在读取数据…', query = '', tab = 'Primary';
  Map? current;
  List<dynamic> items = [], rows = [];
  int epoch = 0;
  String material = 'liquid';
  double fontSize = 14, blur = 18, opacity = .3;
  String backgroundPath = '';
  double backgroundDim = .35;
  Timer? styleTimer;
  Future<void> styleWrite = Future.value();
  final search = TextEditingController();
  final navigator = GlobalKey<NavigatorState>();
  final rowRevision = ValueNotifier<int>(0);
  static const tabs = {
    'Armor': '被动组合',
    'Armors': '护甲、头盔与披风',
    'Presets': '全局预设',
    'Settings': '设置',
    'Primary': '主武器',
    'Secondary': '副武器',
    'Support': '支援武器',
    'Throwables': '投掷物',
    'Stratagems': '战略配备',
    'Mechas': '载具与机甲',
    'Boosters': '强化增益',
    'Attachments': '配件',
    'Helldiver': '潜兵',
    'Terminids': '终结族',
    'Automatons': '机器人',
    'Illuminate': '光能族',
    'SEAF': '超级地球部队',
    'Spawning': '敌人生成',
    'Corpses': '尸体清理',
    'Records': '数据库',
  };
  static const navigation = {
    'Primary': ('装备', Icons.gps_fixed),
    'Stratagems': ('战略配备', Icons.rocket_launch_outlined),
    'Mechas': ('载具机甲', Icons.directions_car_outlined),
    'Armors': ('护甲', Icons.shield_outlined),
    'Helldiver': ('潜兵', Icons.person_outline),
    'Terminids': ('敌人', Icons.pest_control_outlined),
    'Corpses': ('尸体清理', Icons.cleaning_services_outlined),
    'Records': ('数据与预设', Icons.storage_outlined),
    'Settings': ('设置', Icons.tune),
  };
  List<String> peers(String key) {
    for (final group in [
      [
        'Primary',
        'Secondary',
        'Support',
        'Throwables',
        'Boosters',
        'Attachments',
      ],
      ['Armors', 'Armor'],
      ['Terminids', 'Automatons', 'Illuminate', 'SEAF', 'Spawning'],
      ['Records', 'Presets'],
    ]) {
      if (group.contains(key)) return group;
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      if (widget.persistAppearance) await loadStyle();
      await backend.start();
      if (!mounted) return;
      setState(() => ready = true);
      await load('Primary');
    } catch (e) {
      if (mounted) setState(() => status = '启动失败：$e');
    }
  }

  Future<void> load(String key) async {
    final ticket = ++epoch;
    setState(() {
      tab = key;
      current = null;
      query = '';
      search.clear();
      busy = true;
    });
    try {
      if (['Armor', 'Presets', 'Settings', 'Corpses'].contains(key)) {
        setState(() {
          busy = false;
          if (key == 'Corpses') status = '清理设置随「写入游戏」生效';
        });
        return;
      }
      await backend.call('editor_mode', [
        [
          'Terminids',
          'Automatons',
          'Illuminate',
          'SEAF',
          'Spawning',
        ].contains(key),
      ]);
      final result = await backend.call('items', [key, '']);
      if (mounted && ticket == epoch)
        setState(() {
          items = result is List ? result : [];
          status = '${items.length} 个条目';
        });
      if (mounted &&
          ticket == epoch &&
          key == 'Helldiver' &&
          items.length == 1) {
        await select(items.single as Map);
      }
    } catch (e) {
      showError(e);
    } finally {
      if (mounted && ticket == epoch) setState(() => busy = false);
    }
  }

  Future<void> select(Map item) async {
    final ticket = ++epoch;
    setState(() {
      current = item;
      rows = [];
      busy = true;
    });
    try {
      await backend.call('select', [item['id']]);
      final result = await backend.call('rows');
      if (mounted && ticket == epoch)
        setState(() => rows = result is List ? result : []);
    } catch (e) {
      showError(e);
    } finally {
      if (mounted && ticket == epoch) setState(() => busy = false);
    }
  }

  Future<bool> edit(String method, List<dynamic> args) async {
    final ticket = epoch;
    try {
      await backend.call(method, args);
      final result = await backend.call('rows');
      if (mounted && ticket == epoch)
        setState(() {
          rows = result is List ? result : [];
          status = '修改已保存，写入游戏后生效';
        });
      if (mounted && ticket == epoch) rowRevision.value++;
      return true;
    } catch (e) {
      showError(e);
      return false;
    }
  }

  void showError(Object e) {
    if (!mounted) return;
    setState(() => status = e.toString());
    showDialog<void>(
      context: navigator.currentContext ?? context,
      builder: (ctx) => GlassDialog(
        title: const Text('操作未完成'),
        content: SelectableText(e.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> choices(Map row) async {
    try {
      final response = await backend.call('choices', [row['id']]);
      if (!mounted) return;
      final options = response is List ? response : [];
      String filter = '';
      final choice = await showDialog<Map>(
        context: navigator.currentContext ?? context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => GlassDialog(
            title: Text(row['label']),
            content: SizedBox(
              width: 620,
              height: 450,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜索名称或 ID',
                    ),
                    onChanged: (v) => update(() => filter = v.toLowerCase()),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final option in options)
                          if (option.toString().toLowerCase().contains(filter))
                            ListTile(
                              title: Text(
                                '${option['name'] ?? option['label'] ?? option['id']}',
                              ),
                              subtitle: Text(
                                '#${option['id']} · ${option['description'] ?? ''}',
                              ),
                              enabled: option['disabled'] != true,
                              onTap: () => Navigator.pop(ctx, option as Map),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
      if (choice != null) {
        if (['resomode', 'smmode'].contains(row['choice_kind'])) {
          if (choice['id'] == 0) return;
          if (!mounted) return;
          final yes = await showDialog<bool>(
            context: navigator.currentContext ?? context,
            builder: (ctx) => GlassDialog(
              title: const Text('确认修改资源补丁'),
              content: const Text('此操作会立即写入或移除游戏资源补丁。请先关闭游戏，完成后重启生效。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('继续'),
                ),
              ],
            ),
          );
          if (yes != true) return;
        }
        await edit('choose', [row['id'], choice['id']]);
      }
    } catch (e) {
      showError(e);
    }
  }

  Future<void> install() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final preview = await showDialog<dynamic>(
        context: navigator.currentContext!,
        barrierDismissible: false,
        builder: (_) => InstallDialog(backend: backend, preview: true),
      );
      if (preview == null) return;
      if (!mounted) return;
      setState(() => busy = false);
      final problems = preview is Map && preview['problems'] is List
          ? preview['problems'] as List
          : [];
      final yes = await showDialog<bool>(
        context: navigator.currentContext ?? context,
        builder: (ctx) => GlassDialog(
          title: const Text('写入前预览'),
          content: SizedBox(
            width: 640,
            height: 400,
            child: ReviewBody(data: preview),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: problems.isEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('确认写入'),
            ),
          ],
        ),
      );
      if (yes == true) {
        setState(() => busy = true);
        final result = await showDialog<dynamic>(
          context: navigator.currentContext!,
          barrierDismissible: false,
          builder: (_) => InstallDialog(backend: backend),
        );
        if (mounted)
          setState(
            () => status = result is Map
                ? '${result['message'] ?? ''}'
                : '安装窗口已关闭',
          );
      }
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> code(Map row) async {
    final arrows = <int>[];
    final result = await showDialog<List<int>>(
      context: navigator.currentContext ?? context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => GlassDialog(
          title: const Text('录入战备指令'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                arrows.map((x) => ['', '↑', '→', '↓', '←'][x]).join(' '),
                style: const TextStyle(fontSize: 28),
              ),
              Wrap(
                children: [
                  for (int i = 1; i <= 4; i++)
                    IconButton(
                      onPressed: arrows.length >= 9
                          ? null
                          : () => update(() => arrows.add(i)),
                      icon: Icon(
                        [
                          Icons.error,
                          Icons.arrow_upward,
                          Icons.arrow_forward,
                          Icons.arrow_downward,
                          Icons.arrow_back,
                        ][i],
                      ),
                    ),
                  IconButton(
                    onPressed: arrows.isEmpty
                        ? null
                        : () => update(() => arrows.removeLast()),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: arrows.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, arrows),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await edit('code_set', [row['id'], result]);
  }

  Future<void> equipmentPresets() async {
    int slot = 1;
    Map info = {};
    Future<void> refresh() async {
      final x = await backend.call('preset_info', [slot]);
      info = x as Map;
    }

    try {
      await refresh();
      if (!mounted) return;
      await showDialog<void>(
        context: navigator.currentContext ?? context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => GlassDialog(
            title: Text('${current?['name']} · 装备预设'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<int>(
                  segments: [
                    for (int i = 1; i <= 5; i++)
                      ButtonSegment(value: i, label: Text('$i')),
                  ],
                  selected: {slot},
                  onSelectionChanged: (values) async {
                    slot = values.first;
                    await refresh();
                    update(() {});
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  '${info['name']} · ${info['saved'] == true ? '已保存' : '空预设'}',
                ),
              ],
            ),
            actions: [
              for (final op in {
                'save': '保存',
                'load': '读取',
                'clear': '清空',
              }.entries)
                TextButton(
                  onPressed: op.key != 'save' && info['saved'] != true
                      ? null
                      : () async {
                          try {
                            await backend.call('preset', [op.key, slot]);
                            await refresh();
                            update(() {});
                            final x = await backend.call('rows');
                            if (mounted) setState(() => rows = x as List);
                          } catch (e) {
                            showError(e);
                          }
                        },
                  child: Text(op.value),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      showError(e);
    }
  }

  File get styleFile {
    final env = Platform.environment;
    final base =
        env['SHODAN_PROFILE'] ??
        '${env['LOCALAPPDATA'] ?? File(Platform.resolvedExecutable).parent.path}/SHODAN/StatEditor';
    return File('$base/morrow-ui.json');
  }

  Future<void> loadStyle() async {
    try {
      if (!await styleFile.exists()) return;
      final v = jsonDecode(await styleFile.readAsString());
      if (!mounted || v is! Map) return;
      setState(() {
        dark = v['dark'] is bool ? v['dark'] : dark;
        backend.diagnostics.enabled = v['diagnosticMode'] == true;
        backgroundPath = v['backgroundPath'] is String
            ? v['backgroundPath']
            : '';
        backgroundDim = v['backgroundDim'] is num
            ? (v['backgroundDim'] as num).toDouble().clamp(0, .9)
            : backgroundDim;
        material = ['liquid', 'frosted', 'clear'].contains(v['material'])
            ? v['material']
            : material;
        fontSize = v['fontSize'] is num
            ? (v['fontSize'] as num).toDouble().clamp(12, 24)
            : fontSize;
        blur = v['blur'] is num
            ? (v['blur'] as num).toDouble().clamp(0, 40)
            : blur;
        opacity = v['opacity'] is num
            ? (v['opacity'] as num).toDouble().clamp(.08, .85)
            : opacity;
      });
    } catch (_) {
      if (mounted) setState(() => status = '外观设置无法读取，已使用默认外观');
    }
  }

  void saveStyle() {
    if (!widget.persistAppearance) return;
    {
      final text = jsonEncode({
        'dark': dark,
        'material': material,
        'fontSize': fontSize,
        'blur': blur,
        'opacity': opacity,
        'backgroundPath': backgroundPath,
        'backgroundDim': backgroundDim,
        'diagnosticMode': backend.diagnostics.enabled,
      });
      styleWrite = styleWrite.catchError((_) {}).then((_) async {
        try {
          final f = styleFile;
          await f.parent.create(recursive: true);
          await f.writeAsString(text, flush: true);
        } catch (_) {
          if (mounted) setState(() => status = '外观设置保存失败，请检查配置目录权限');
        }
      });
    }
  }

  Future<void> shutdown() async {
    // All settings are queued at the time of the operation, not on close.
    await styleWrite;
  }

  Widget settingsPage() => ListView(
    children: [
      surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '日志与诊断',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('诊断模式'),
              subtitle: const Text('额外记录接口耗时和安装阶段；不记录输入的文字或预设内容。设置在重启后保留。'),
              value: backend.diagnostics.enabled,
              onChanged: (v) {
                setState(() => backend.diagnostics.enabled = v);
                backend.diagnostics.record('诊断模式${v ? '开启' : '关闭'}');
                saveStyle();
              },
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: diagnosing
                      ? null
                      : () async {
                          setState(() => diagnosing = true);
                          try {
                            final text = await backend.diagnose();
                            if (mounted)
                              setState(() => diagnosticResult = text);
                          } catch (e) {
                            showError(e);
                          } finally {
                            if (mounted) setState(() => diagnosing = false);
                          }
                        },
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('运行只读诊断'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final saved = await exportDiagnostics(
                        backend.diagnostics,
                      );
                      if (saved && mounted)
                        setState(() => diagnosticResult = '诊断日志已导出。');
                    } catch (e) {
                      showError('日志导出失败：$e');
                    }
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('导出诊断日志'),
                ),
              ],
            ),
            if (diagnosing) const LinearProgressIndicator(),
            if (diagnosticResult.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(diagnosticResult),
              ),
            const SizedBox(height: 8),
            const Text('检查运行文件、数据引擎和游戏目录，不写入游戏。导出内容含运行环境、错误和最近启动日志，不会自动上传。'),
          ],
        ),
      ),
      const SizedBox(height: 16),
      surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '自定义背景',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text('选择本地图片，裁剪填满工作台；浅色模式使用浅色遮罩，深色模式使用深色遮罩，保持文字清晰。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      final image = await openFile(
                        acceptedTypeGroups: [
                          const XTypeGroup(
                            label: '背景图片',
                            extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
                          ),
                        ],
                      );
                      if (image == null || !mounted) return;
                      // Decode before accepting, so an invalid file cannot blank the background.
                      final bytes = await image.readAsBytes();
                      final codec = await ui.instantiateImageCodec(bytes);
                      final frame = await codec.getNextFrame();
                      frame.image.dispose();
                      codec.dispose();
                      if (!mounted) return;
                      setState(() => backgroundPath = image.path);
                      saveStyle();
                    } catch (e) {
                      showError('图片读取失败：$e');
                    }
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('选择图片'),
                ),
                OutlinedButton(
                  onPressed: backgroundPath.isEmpty
                      ? null
                      : () {
                          setState(() => backgroundPath = '');
                          saveStyle();
                        },
                  child: const Text('恢复默认背景'),
                ),
              ],
            ),
            if (backgroundPath.isNotEmpty)
              Text(
                backgroundPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text('背景遮罩 · ${(backgroundDim * 100).round()}%'),
            PreferenceSlider(
              value: backgroundDim,
              min: 0,
              max: .9,
              onChanged: (v) {
                setState(() => backgroundDim = v);
                saveStyle();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '外观与阅读',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('深色模式'),
              subtitle: const Text('切换整个工作台的背景和文字颜色'),
              value: dark,
              onChanged: (v) {
                setState(() => dark = v);
                saveStyle();
              },
            ),
            const SizedBox(height: 16),
            const Text('卡片材质'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'liquid', label: Text('液态玻璃')),
                ButtonSegment(value: 'frosted', label: Text('磨砂')),
                ButtonSegment(value: 'clear', label: Text('通透')),
              ],
              selected: {material},
              onSelectionChanged: (v) {
                setState(() => material = v.first);
                saveStyle();
              },
            ),
            const SizedBox(height: 16),
            Text('字体大小 · ${fontSize.round()}'),
            PreferenceSlider(
              value: fontSize,
              min: 12,
              max: 24,
              divisions: 12,
              onChanged: (v) {
                setState(() => fontSize = v);
                saveStyle();
              },
            ),
            Text('磨砂模糊 · ${blur.round()}'),
            PreferenceSlider(
              value: blur,
              min: 0,
              max: 40,
              onChanged: material == 'frosted'
                  ? (v) {
                      setState(() => blur = v);
                      saveStyle();
                    }
                  : null,
            ),
            Text('卡片底色不透明度 · ${(opacity * 100).round()}%'),
            PreferenceSlider(
              value: opacity,
              min: .08,
              max: .85,
              onChanged: material != 'liquid'
                  ? (v) {
                      setState(() => opacity = v);
                      saveStyle();
                    }
                  : null,
            ),
            const Text('松开滑条应用外观，设置自动保存，重启后保留。'),
          ],
        ),
      ),
      const SizedBox(height: 16),
      surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '程序与游戏路径',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text('4.6.0 · Rust Host + Lua 数据兼容层'),
            const Text('界面字体：MiSans（小米），保留中英文及常用符号。'),
            const Text('游戏路径由现有核心自动检测，不固定其他人的安装目录。'),
            const SizedBox(height: 8),
            const SelectableText('https://github.com/127MU/SHODAN-Stat-Editor'),
          ],
        ),
      ),
    ],
  );
  GlassAppearance get appearance =>
      GlassAppearance(mode: material, dark: dark, blur: blur, opacity: opacity);
  Widget surface(Widget child, {Key? key}) => appearance.wrap(
    Padding(padding: const EdgeInsets.all(20), child: child),
    key: key,
  );

  Widget field(Map row) => surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row['label'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (row['help'] is List && (row['help'] as List).isNotEmpty)
              Tooltip(
                message: (row['help'] as List).join('\n'),
                child: const Icon(Icons.help_outline, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '原值 ${displayNumber(row['default_text'])}',
          style: TextStyle(
            fontSize: 12,
            color: dark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: row['code'] == true
                  ? OutlinedButton(
                      onPressed: () => code(row),
                      child: Text('${row['text']} · 录入指令'),
                    )
                  : row['flag'] == true
                  ? SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row['value'] == 1 ? '开' : '关'),
                      value: (row['value'] as num? ?? 0) >= .5,
                      onChanged: (on) =>
                          edit('set', [row['id'], on ? '1' : '0']),
                    )
                  : row['choice'] == true
                  ? OutlinedButton(
                      onPressed: () => choices(row),
                      child: Text(row['choice_name'] ?? '选择条目'),
                    )
                  : ValueInput(
                      key: ValueKey('${current?['id']}:${row['id']}'),
                      value: '${row['text'] ?? row['value']}',
                      onSave: (value) async {
                        if (!await edit('set', [row['id'], value]))
                          throw StateError('保存失败');
                      },
                    ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '恢复原值',
              onPressed: () => edit('reset', [row['id']]),
              icon: const Icon(Icons.restore),
            ),
          ],
        ),
        if ((row['inline_note'] ?? '').toString().isNotEmpty)
          Text(row['inline_note']),
        if (row['changed'] == true) const Text('已修改'),
      ],
    ),
  );
  Widget parameterPage() {
    final filtered = rows
        .where((r) => r.toString().toLowerCase().contains(query))
        .toList();
    final sections = filtered.map((r) => r['section'] ?? '参数').toSet();
    return CustomScrollView(
      key: PageStorageKey('parameter-categories:${current?['id']}'),
      slivers: [
        if (tab == 'Armors')
          SliverToBoxAdapter(
            child: ArmorItem(
              key: ValueKey(current?['id']),
              backend: backend,
              hash: current!['id'],
              onError: showError,
            ),
          ),
        SliverToBoxAdapter(
          child: GameTextPanel(
            key: ValueKey('text:${current?['id']}'),
            backend: backend,
            onError: showError,
          ),
        ),
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 190 * fontSize / 14,
          ),
          delegate: SliverChildListDelegate([
            for (final section in sections)
              surface(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$section',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${filtered.where((r) => (r['section'] ?? '参数') == section).length} 项参数',
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () => openSection('$section'),
                        child: const Text('打开'),
                      ),
                    ),
                  ],
                ),
                key: ValueKey('section:$section'),
              ),
          ]),
        ),
      ],
    );
  }

  Future<void> openSection(String section) async {
    await showDialog<void>(
      context: navigator.currentContext!,
      builder: (ctx) => GlassDialog(
        title: Text('${current?['name']} · $section'),
        content: SizedBox(
          width: 1300,
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: ValueListenableBuilder<int>(
            valueListenable: rowRevision,
            builder: (context, _, _) => LayoutBuilder(
              builder: (context, box) {
                final width = (box.maxWidth - 48) / 4;
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final r in rows)
                        if ((r['section'] ?? '参数') == section &&
                            r.toString().toLowerCase().contains(query))
                          SizedBox(width: width, child: field(r as Map)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(ctx).unfocus();
              Navigator.pop(ctx);
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorSchemeSeed: const Color(0xff818cf8),
      fontFamily: 'MiSans',
      extensions: [appearance],
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(textTheme: theme.textTheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(fontSize / 14)),
        child: child!,
      ),
      navigatorKey: navigator,
      home: Scaffold(
        body: DesktopFrame(
          enabled: widget.persistAppearance,
          onClose: shutdown,
          child: BackdropGroup(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: backgroundPath.isEmpty
                    ? null
                    : DecorationImage(
                        image: FileImage(File(backgroundPath)),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          (dark ? Colors.black : Colors.white).withValues(
                            alpha: backgroundDim,
                          ),
                          BlendMode.srcOver,
                        ),
                        onError: (_, _) {
                          if (mounted)
                            setState(() {
                              backgroundPath = '';
                              status = '背景图片无法读取，已使用默认背景';
                            });
                        },
                      ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [
                          const Color(0xff101427),
                          const Color(0xff292038),
                          const Color(0xff153033),
                        ]
                      : [
                          const Color(0xffdce9ff),
                          const Color(0xfff4dfef),
                          const Color(0xffdef4ee),
                        ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220 + (fontSize - 14).clamp(0, 10) * 5,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: surface(
                          Column(
                            children: [
                              Image.asset(
                                'assets/shodan.png',
                                width: 48,
                                height: 48,
                              ),
                              const Text(
                                'SHODAN',
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text('4.6.0'),
                              const SizedBox(height: 20),
                              Expanded(
                                child: ListView(
                                  children: [
                                    for (final entry in navigation.entries)
                                      ListTile(
                                        key: ValueKey(
                                          'navigation-${entry.key}',
                                        ),
                                        selected:
                                            tab == entry.key ||
                                            peers(entry.key).contains(tab),
                                        visualDensity: VisualDensity.compact,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                        minLeadingWidth: 24,
                                        horizontalTitleGap: 8,
                                        leading: Icon(entry.value.$2, size: 20),
                                        title: Text(
                                          entry.value.$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: ready && !busy
                                            ? () => load(entry.key)
                                            : null,
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '切换深浅色',
                                onPressed: () {
                                  setState(() => dark = !dark);
                                  saveStyle();
                                },
                                icon: Icon(
                                  dark ? Icons.light_mode : Icons.dark_mode,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (current != null)
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => current = null),
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                Expanded(
                                  child: Text(
                                    current?['name'] ?? tabs[tab]!,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (current != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: OutlinedButton(
                                      onPressed: busy ? null : equipmentPresets,
                                      child: const Text('装备预设'),
                                    ),
                                  ),
                                FilledButton.icon(
                                  onPressed: ready && !busy ? install : null,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('写入游戏'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (current == null && peers(tab).length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final key in peers(tab))
                                      ChoiceChip(
                                        label: Text(
                                          key == 'Armors' ? '护甲装备' : tabs[key]!,
                                        ),
                                        selected: tab == key,
                                        onSelected: busy
                                            ? null
                                            : (_) => load(key),
                                      ),
                                  ],
                                ),
                              ),
                            if (tab != 'Settings' && tab != 'Corpses')
                              TextField(
                                controller: search,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText: current == null
                                      ? '搜索名称、型号或 ID'
                                      : '查找参数',
                                ),
                                onChanged: (value) =>
                                    setState(() => query = value.toLowerCase()),
                              ),
                            const SizedBox(height: 20),
                            if (busy) const LinearProgressIndicator(),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: Duration.zero,
                                layoutBuilder: (current, previous) =>
                                    current ?? const SizedBox.shrink(),
                                transitionBuilder: (child, animation) =>
                                    IgnorePointer(
                                      ignoring:
                                          animation.status ==
                                          AnimationStatus.reverse,
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    '$tab:${current?["id"] ?? "catalog"}',
                                  ),
                                  child: tab == 'Settings'
                                      ? settingsPage()
                                      : tab == 'Corpses'
                                      ? CorpseCleanupPage(
                                          backend: backend,
                                          onError: showError,
                                        )
                                      : tab == 'Armor'
                                      ? ArmorPage(
                                          backend: backend,
                                          onError: showError,
                                          surface: (child) => surface(child),
                                        )
                                      : tab == 'Presets'
                                      ? PresetPage(
                                          backend: backend,
                                          onError: showError,
                                        )
                                      : current == null
                                      ? LayoutBuilder(
                                          builder: (context, box) {
                                            const columns = 4;
                                            final visible = items
                                                .where(
                                                  (x) => x
                                                      .toString()
                                                      .toLowerCase()
                                                      .contains(query),
                                                )
                                                .toList();
                                            return GridView.builder(
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: columns,
                                                    mainAxisExtent:
                                                        170 * (fontSize / 14),
                                                    crossAxisSpacing: 16,
                                                    mainAxisSpacing: 16,
                                                  ),
                                              itemCount: visible.length,
                                              itemBuilder: (context, i) {
                                                final item = visible[i] as Map;
                                                return surface(
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        item['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontSize: 19,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        item['changed'] == true
                                                            ? '已修改'
                                                            : '原版参数',
                                                      ),
                                                      const Spacer(),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child:
                                                            FilledButton.tonal(
                                                              onPressed: () =>
                                                                  select(item),
                                                              child: const Text(
                                                                '打开',
                                                              ),
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  key: ValueKey(
                                                    'item:${item['id']}',
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        )
                                      : parameterPage(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    styleTimer?.cancel();
    rowRevision.dispose();
    search.dispose();
    backend.close().catchError((_) {});
    super.dispose();
  }
}

class ValueInput extends StatefulWidget {
  const ValueInput({super.key, required this.value, required this.onSave});
  final String value;
  final Future<void> Function(String) onSave;
  @override
  State<ValueInput> createState() => _ValueInputState();
}

class _ValueInputState extends State<ValueInput> {
  late final c = TextEditingController(text: displayNumber(widget.value));
  final focus = FocusNode();
  String saved = '';
  bool saving = false;
  bool queued = false;
  @override
  void initState() {
    super.initState();
    saved = c.text;
    focus.addListener(() {
      if (!focus.hasFocus) save();
    });
  }

  Future<void> save() async {
    if (saving) {
      queued = true;
      return;
    }
    if (c.text == saved) return;
    saving = true;
    do {
      queued = false;
      final value = c.text;
      try {
        await widget.onSave(value);
        saved = value;
      } catch (_) {
        if (mounted) c.text = saved;
        queued = false;
        break;
      }
    } while (mounted && queued && c.text != saved);
    if (mounted && c.text == saved) {
      c.text = displayNumber(saved);
      saved = c.text;
    }
    saving = false;
  }

  @override
  void didUpdateWidget(covariant ValueInput old) {
    super.didUpdateWidget(old);
    if (!saving && !focus.hasFocus && widget.value != old.value) {
      c.text = displayNumber(widget.value);
      saved = c.text;
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: c,
    focusNode: focus,
    onSubmitted: (_) => save(),
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
  @override
  void dispose() {
    focus.dispose();
    c.dispose();
    super.dispose();
  }
}
