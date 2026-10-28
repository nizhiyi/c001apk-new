import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/device_identity_action.dart';
import '../../components/keyboard_scroll_region.dart';
import '../../components/liquid_navigation_bar.dart';
import '../../logic/content_filter/content_filter_rule.dart';
import '../../logic/onboarding/onboarding_state.dart';
import '../../logic/szlm_identity_service.dart';
import '../settings/device_identity_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.state,
    this.initial = false,
    this.onFinished,
    this.identityService,
  });

  final OnboardingState state;
  final bool initial;
  final VoidCallback? onFinished;
  final SzlmIdentityService? identityService;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _steps = ['发布偏好', '外观', '内容屏蔽', '数盟 ID'];
  late final OnboardingDraft _draft;
  final _scroll = ScrollController();
  int _step = 0;
  bool _saving = false;
  bool _canPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.state.createDraft();
    widget.state.begin();
  }

  @override
  void dispose() {
    widget.state.end();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    if (_saving) return;
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_saving) return;
    if (_step > 0) {
      _go(_step - 1);
    } else {
      unawaited(_cancel());
    }
  }

  void _leave() {
    if (widget.initial) {
      widget.onFinished?.call();
    } else {
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _cancel() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.initial) {
        await widget.state.skip();
      }
      if (mounted) _leave();
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。已有设置不会被清空。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.finish(_draft);
      // Reopened routes remain visible during their exit animation. Keep
      // automatic prompts and external links paused until dispose releases it.
      if (!widget.initial && mounted) widget.state.begin();
      if (mounted) _leave();
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。已保存的项目会保留。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice({
    Key? key,
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    Widget? preview,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: key,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color:
            selected ? colors.secondaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(description),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked),
                ]),
                if (preview != null) ...[
                  const SizedBox(height: 16),
                  preview,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String description) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(description),
        ]),
      );

  Widget _content() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (_step) {
          0 => [
              _heading('你打算发布内容吗？', '选择适合你的主页，之后可随时在设置中调整。'),
              _choice(
                  title: '主要浏览，不写东西',
                  description: '隐藏手机与桌面主页的发布入口。',
                  icon: Icons.auto_stories_outlined,
                  selected: _draft.hidePublish,
                  onTap: () => setState(() => _draft.hidePublish = true)),
              _choice(
                  title: '我也会发布',
                  description: '保留发布入口，想分享时再登录。',
                  icon: Icons.edit_outlined,
                  selected: !_draft.hidePublish,
                  onTap: () => setState(() => _draft.hidePublish = false)),
            ],
          1 => [
              _heading('选择喜欢的外观', '配色、深浅色、字号和玻璃档位都会保留。'),
              if (_draft.appearance == OnboardingAppearance.custom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('当前自定义外观',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              _choice(
                title: 'M3E',
                description: '标准 Material 3 Expressive 控件，关闭悬浮效果。',
                icon: Icons.dashboard_outlined,
                selected: _draft.appearance == OnboardingAppearance.m3e,
                onTap: () => setState(
                    () => _draft.appearance = OnboardingAppearance.m3e),
                preview: const _AppearancePreview(glass: false),
              ),
              _choice(
                title: '液态玻璃',
                description: '悬浮控件与透亮玻璃效果，可调节效果程度。',
                icon: Icons.blur_on,
                selected: _draft.appearance == OnboardingAppearance.glass,
                onTap: () => setState(
                    () => _draft.appearance = OnboardingAppearance.glass),
                preview: const _AppearancePreview(glass: true),
              ),
              const Text('预览只在这里展示，完成引导后才应用。高级选项可在外观设置中调整。'),
            ],
          2 => [
              _heading('屏蔽傻逼内容', '减少低俗内容打扰，让浏览更清爽'),
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: SwitchListTile(
                  key: const ValueKey('onboarding-filter-enabled'),
                  title: const Text('开启内容屏蔽'),
                  subtitle: const Text('仅改变本机展示，可随时在设置中调整'),
                  value: _draft.filterEnabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _draft.filterEnabled = value),
                ),
              ),
              if (_draft.filterEnabled) ...[
                _choice(
                    key: const ValueKey('onboarding-filter-standard'),
                    title: '标准',
                    description: '减少明确的低俗内容打扰。',
                    icon: Icons.shield_outlined,
                    selected: _draft.filterLevel == FilterLevel.standard,
                    onTap: () => setState(
                        () => _draft.filterLevel = FilterLevel.standard)),
                _choice(
                    key: const ValueKey('onboarding-filter-strict'),
                    title: '严格',
                    description: '更强过滤，误杀可能更多',
                    icon: Icons.shield,
                    selected: _draft.filterLevel == FilterLevel.strict,
                    onTap: () => setState(
                        () => _draft.filterLevel = FilterLevel.strict)),
              ],
              const Text('开启后会检查订阅规则，下载失败仍使用内置或缓存规则。'
                  '已有分类选择、个人规则和例外都会保留。'),
            ],
          _ => [
              _heading(
                  '准备设备标识',
                  '数盟 ID 用于酷安请求，有助于减少重复人机验证；'
                      '互动是否可用仍取决于账号与服务端。'),
              DeviceIdentityAction(service: widget.identityService),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DeviceIdentityPage(
                                identityService: widget.identityService),
                          )),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('手动导入'),
                ),
                TextButton(
                    onPressed: _saving ? null : _finish,
                    child: const Text('稍后设置')),
              ]),
            ],
        },
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('使用引导',
                    style: Theme.of(context).textTheme.titleLarge)),
            TextButton(
              onPressed: _saving ? null : _cancel,
              child: Text(widget.initial ? '跳过引导' : '取消'),
            ),
          ]),
          const SizedBox(height: 8),
          Text('${_step + 1} / 4'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: (_step + 1) / 4,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: '第 ${_step + 1} 步，共 4 步：${_steps[_step]}'),
        ]),
      );

  Widget _footer() => Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) ...[
            Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 12),
          ],
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (_step > 0)
                  OutlinedButton(
                      onPressed: _saving ? null : _back,
                      child: const Text('上一步')),
                FilledButton(
                  key: const ValueKey('onboarding-next'),
                  onPressed: _saving
                      ? null
                      : _step < 3
                          ? () => _go(_step + 1)
                          : _finish,
                  child: Text(_saving
                      ? '正在保存…'
                      : _step < 3
                          ? '下一步'
                          : '完成'),
                ),
              ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey != LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) _back();
            return KeyEventResult.handled;
          },
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final compact = constraints.maxHeight < 520 * scale;
                final wide = constraints.maxWidth >= 960 * scale.clamp(1, 1.5);
                final content = Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _content());
                final body = compact
                    ? SingleChildScrollView(
                        controller: _scroll,
                        child: Column(children: [
                          _header(),
                          content,
                          _footer(),
                        ]))
                    : Column(children: [
                        _header(),
                        Expanded(
                            child: SingleChildScrollView(
                                controller: _scroll, child: content)),
                        _footer(),
                      ]);
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Row(children: [
                      if (wide && !compact)
                        SizedBox(
                          width: 240,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < _steps.length; i++)
                                    ListTile(
                                      selected: i == _step,
                                      leading: CircleAvatar(
                                          child: i < _step
                                              ? const Icon(Icons.check)
                                              : Text('${i + 1}')),
                                      title: Text(_steps[i]),
                                    ),
                                ]),
                          ),
                        ),
                      Expanded(child: KeyboardScrollRegion(child: body)),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      );
}

/// A miniature of the app's real navigation controls, without global writes.
class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.glass});
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: SizedBox(
            height: 132,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.noScaling),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 320,
                    height: 132,
                    color: colors.surface,
                    child: Stack(children: [
                      Positioned.fill(
                          child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          for (final color in [
                            colors.primaryContainer,
                            colors.secondaryContainer,
                            colors.tertiaryContainer,
                          ])
                            Expanded(
                                child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(16)),
                            )),
                        ]),
                      )),
                      Positioned(
                        left: glass ? 12 : 0,
                        right: glass ? 12 : 0,
                        bottom: glass ? 8 : 0,
                        child: glass
                            ? LiquidNavigationBar(
                                selectedIndex: 0,
                                onDestinationSelected: (_) {},
                              )
                            : NavigationBar(
                                selectedIndex: 0,
                                onDestinationSelected: (_) {},
                                destinations: const [
                                  NavigationDestination(
                                      icon: Icon(Icons.home_outlined),
                                      label: '主页'),
                                  NavigationDestination(
                                      icon: Icon(Icons.feed_outlined),
                                      label: '关注'),
                                  NavigationDestination(
                                      icon: Icon(Icons.person_outline),
                                      label: '我的'),
                                ],
                              ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
