// ignore_for_file: constant_identifier_names

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/mouse_drag_scroll.dart';
import '../../components/liquid_top_bar.dart';
import '../../components/liquid_navigation_bar.dart';
import '../../utils/storage_util.dart';
import '../../pages/home/app/app_list_page.dart';
import '../../pages/home/feed/home_feed_page.dart';
import '../../pages/home/return_top_controller.dart';
import '../../pages/home/topic/home_topic_page.dart';

enum TabType {
  FOLLOW,
  APP,
  FEED,
  HOT,
  TOPIC,
  PRODUCT,
  COOLPIC,
  NONE;

  String get label => switch (this) {
        TabType.FOLLOW => '关注',
        TabType.APP => '应用',
        TabType.FEED => '动态',
        TabType.HOT => '热门',
        TabType.TOPIC => '话题',
        TabType.PRODUCT => '数码',
        TabType.COOLPIC => '酷图',
        TabType.NONE => '其他',
      };
}

class HomePage extends StatefulWidget {
  const HomePage(
      {super.key,
      this.useRail = false,
      this.onFeedSelected,
      this.onPublishVisibilityChanged});

  final bool useRail;
  final ValueChanged<bool>? onFeedSelected, onPublishVisibilityChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<int>? _returnTopSubscription;
  final ReturnTopController _pageScrollController =
      Get.find<ReturnTopController>(tag: 'home');
  // late final _config = Provider.of<AppConfigProvider>(context, listen: false);
  // late bool _showFab = true; //_config.isLogin;

  final _tabTypes = [
    if (Platform.isAndroid) TabType.APP,
    TabType.FEED,
    TabType.HOT,
    TabType.TOPIC,
    TabType.PRODUCT,
    TabType.COOLPIC,
  ];

  List<Widget> get _pages => [
        if (Platform.isAndroid) const AppListPage(),
        HomeFeedPage(
            tabType: TabType.FEED,
            useRail: widget.useRail,
            onPublishVisibilityChanged: widget.onPublishVisibilityChanged),
        const HomeFeedPage(tabType: TabType.HOT),
        const HomeTopicPage(tabType: TabType.TOPIC),
        const HomeTopicPage(tabType: TabType.PRODUCT),
        const HomeFeedPage(tabType: TabType.COOLPIC),
      ];

  void scrollToTop(int index) {
    _pageScrollController.setIndex(_tabTypes[index].index);
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      vsync: this,
      initialIndex: _tabTypes.indexOf(TabType.FEED),
      length: _tabTypes.length,
    );
    _tabController.addListener(() => widget.onFeedSelected
        ?.call(_tabTypes[_tabController.index] == TabType.FEED));

    _returnTopSubscription = _pageScrollController.index.listen((index) {
      if (index == 998) {
        scrollToTop(_tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _returnTopSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidTopBarScaffold(
      glassTitle: (context) => AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) => LiquidNavigationBar.tabs(
          selectedIndex: _tabController.index,
          labels: _tabTypes.map((type) => type.label).toList(),
          level: GStorage.liquidGlassLevel,
          onDestinationSelected: (index) {
            if (_tabController.index == index) {
              scrollToTop(index);
            } else {
              _tabController.animateTo(index);
            }
          },
        ),
      ),
      title: MouseDragScroll(
        child: TabBar(
          controller: _tabController,
          tabs: _tabTypes.map((type) => Tab(text: type.label)).toList(),
          isScrollable: true,
          dividerColor: Theme.of(context).platform == TargetPlatform.android
              ? Colors.transparent
              : null,
          tabAlignment: Theme.of(context).platform == TargetPlatform.android
              ? TabAlignment.start
              : null,
          onTap: (index) {
            if (!_tabController.indexIsChanging) {
              scrollToTop(index);
            }
          },
        ),
      ),
      onSearch: () => Get.toNamed('/search'),
      body: TabBarView(controller: _tabController, children: _pages),
    );
  }
}
