import 'package:flutter/material.dart';
import 'backend.dart';

class CorpseCleanupPage extends StatefulWidget {
  const CorpseCleanupPage({
    super.key,
    required this.backend,
    required this.onError,
  });
  final Backend backend;
  final void Function(Object) onError;

  @override
  State<CorpseCleanupPage> createState() => _CorpseCleanupPageState();
}

class _CorpseCleanupPageState extends State<CorpseCleanupPage> {
  Map<String, dynamic>? data;
  bool saving = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    read();
  }

  Future<void> read() async {
    try {
      final result = await widget.backend.call('corpse_status');
      if (mounted)
        setState(() => data = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (mounted) setState(() => failure = '$e');
    }
  }

  dynamic get fragments =>
      data?['fragments'] == 'custom' ? 'custom' : data?['fragments'] == 'fast';

  Future<void> save(String mode, dynamic gore, {bool reset = false}) async {
    setState(() => saving = true);
    try {
      final result = await widget.backend.call(
        reset ? 'corpse_reset' : 'corpse_set',
        reset ? [] : [mode, gore],
      );
      if (mounted)
        setState(() => data = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('读取尸体清理设置失败：$failure'),
          TextButton(onPressed: read, child: const Text('重试')),
        ],
      );
    }
    if (data == null) return const Center(child: CircularProgressIndicator());
    final supported = data!['supported'] == true;
    final enabled = supported && !saving;
    final mode = '${data!['mode'] ?? 'original'}';
    return ListView(
      key: const PageStorageKey('corpse-cleanup-page'),
      children: [
        const Text(
          '清理尸体与碎块',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('选择清理方式后，点击右上角「写入游戏」，与其他数值一起安装。完成后重新启动游戏。'),
        const SizedBox(height: 20),
        if (data!['problem'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              '${data!['problem']}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (saving) const LinearProgressIndicator(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '尸体消退',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('corpse-mode-$mode'),
                  initialValue: mode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '清理模式',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'original',
                      child: Text('原版'),
                    ),
                    const DropdownMenuItem(
                      value: 'fast',
                      child: Text('快速清场 · 约 6 秒'),
                    ),
                    const DropdownMenuItem(
                      value: 'instant',
                      child: Text('小型单位快速消失'),
                    ),
                    if (mode == 'custom')
                      const DropdownMenuItem(
                        value: 'custom',
                        child: Text('保留已有自定义设置'),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) {
                          if (value != null) save(value, fragments);
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                const Text('快速清场：使用约 6 秒消退与 300 米清尸半径；特殊巨型单位保留配方中的较长延迟。'),
                const SizedBox(height: 8),
                const Text('小型单位快速消失：使用原补丁的即时消退设置。大型单位的实际消退动作仍取决于游戏。'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: CheckboxListTile(
            key: const ValueKey('corpse-fragments'),
            contentPadding: const EdgeInsets.all(20),
            title: const Text('碎块 2 秒清理'),
            subtitle: Text(
              data!['fragments'] == 'custom'
                  ? '当前有自定义碎块设置；勾选后统一使用 2 秒寿命。'
                  : '可与两种尸体模式组合使用；关闭后恢复原版碎块寿命。',
            ),
            tristate: true,
            value: data!['fragments'] == 'custom'
                ? null
                : data!['fragments'] == 'fast',
            onChanged: enabled
                ? (value) => save(
                    mode,
                    data!['fragments'] == 'custom' ? true : value ?? false,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('corpse-combined'),
              onPressed: enabled ? () => save('fast', true) : null,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('快速清场＋碎块清理'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => save('instant', true) : null,
              child: const Text('套用小型单位补丁'),
            ),
            TextButton.icon(
              key: const ValueKey('corpse-reset'),
              onPressed: !saving && (supported || data!['saved'] == true)
                  ? () => save('original', false, reset: true)
                  : null,
              icon: const Icon(Icons.restore),
              label: Text(supported ? '恢复原版清理参数' : '停用旧清理配置'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          data!['changed'] == true
              ? '清理参数已有待写入修改；可在「写入游戏」中查看预览。'
              : '设置已读取；此页面的选择不会立即修改游戏文件。',
        ),
      ],
    );
  }
}
