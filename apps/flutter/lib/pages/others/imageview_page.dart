import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../utils/download_util.dart';
import '../../utils/utils.dart';

class ImageViewPage extends StatefulWidget {
  const ImageViewPage({super.key});

  @override
  State<ImageViewPage> createState() => _ImageViewPageState();
}

class _ImageViewPageState extends State<ImageViewPage> {
  late int _currentPage;
  late final List<String> _imgList;
  late final PageController _pageController;
  final _galleryKey = GlobalKey();
  final _controllers = <int, PhotoViewController>{};
  final _scaleStates = <int, PhotoViewScaleStateController>{};
  final _providers = <int, CachedNetworkImageProvider>{};
  final _imageSizes = <int, Size>{};
  final _imageListeners = <int, (ImageStream, ImageStreamListener)>{};
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _imgList = List<String>.from(Get.arguments['imgList'] ?? const <String>[]);
    final int initialPage = Get.arguments['initialPage'] ?? 0;
    _currentPage = initialPage.clamp(0, math.max(0, _imgList.length - 1));
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    for (final (stream, listener) in _imageListeners.values) {
      stream.removeListener(listener);
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final state in _scaleStates.values) {
      state.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  CachedNetworkImageProvider _providerFor(int index) {
    final provider = _providers.putIfAbsent(
        index, () => CachedNetworkImageProvider(_imgList[index]));
    if (!_imageSizes.containsKey(index) &&
        !_imageListeners.containsKey(index)) {
      final stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      void stopListening() {
        stream.removeListener(listener);
        _imageListeners.remove(index);
      }

      listener = ImageStreamListener((info, _) {
        _imageSizes[index] =
            Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        stopListening();
      }, onError: (Object error, StackTrace? stack) => stopListening());
      _imageListeners[index] = (stream, listener);
      stream.addListener(listener);
    }
    return provider;
  }

  void _changePage(int delta) {
    if (_menuOpen || !_pageController.hasClients || _imgList.isEmpty) return;
    final current = (_pageController.page ?? _currentPage.toDouble()).round();
    final next = (current + delta).clamp(0, _imgList.length - 1);
    if (next == current) return;
    unawaited(_pageController.animateToPage(next,
        duration: const Duration(milliseconds: 255), curve: Curves.ease));
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        _menuOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _changePage(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _changePage(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        _menuOpen) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final controller = _controllers[_currentPage];
      final imageSize = _imageSizes[_currentPage];
      final box = _galleryKey.currentContext?.findRenderObject();
      if (controller?.scale == null ||
          imageSize == null ||
          box is! RenderBox ||
          !box.hasSize) return;
      final minimum = math.min(
          box.size.width / imageSize.width, box.size.height / imageSize.height);
      final maximum = math.max(box.size.width / imageSize.width,
              box.size.height / imageSize.height) *
          8;
      final scale = controller!.scale!;
      final next =
          (scale * math.exp((-event.scrollDelta.dy * 0.0015).clamp(-20, 20)))
              .clamp(minimum, maximum)
              .toDouble();
      final anchor =
          box.globalToLocal(event.position) - box.size.center(Offset.zero);
      controller.updateMultiple(
        scale: next,
        position: anchor - (anchor - controller.position) * (next / scale),
      );
      // PhotoView can clamp the anchored position before updating its scale
      // state. Keep that state in sync when a gallery page is recreated.
      _scaleStates[_currentPage]?.setInvisibly(next > minimum
          ? PhotoViewScaleState.zoomedIn
          : PhotoViewScaleState.initial);
    });
  }

  Future<void> _showImageMenu() async {
    if (_menuOpen || _imgList.isEmpty) return;
    _menuOpen = true;
    final imageUrl = _imgList[_currentPage];
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          clipBehavior: Clip.hardEdge,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('保存图片', style: TextStyle(fontSize: 14)),
                onTap: () {
                  DownloadUtils.downloadImg([imageUrl]);
                  Get.back();
                },
              ),
              if (_imgList.length != 1)
                ListTile(
                  title: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    DownloadUtils.downloadImg(_imgList);
                    Get.back();
                  },
                ),
              ListTile(
                title: const Text('分享', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Utils.onShareImg(imageUrl);
                  Get.back();
                },
              ),
              ListTile(
                title: const Text('复制', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Utils.copyText(imageUrl);
                  Get.back();
                },
              ),
              if (Utils.isDesktop)
                ListTile(
                  title: const Text('在浏览器中打开', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Utils.launchURL(imageUrl);
                    Get.back();
                  },
                ),
            ],
          ),
        ),
      );
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Scaffold(
          appBar: AppBar(
            title: Text([
              _imgList.isEmpty ? 0 : _currentPage + 1,
              _imgList.length
            ].join('/')),
          ),
          body: _imgList.isEmpty
              ? const Center(child: Text('暂无图片'))
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Listener(
                      key: _galleryKey,
                      onPointerSignal: _onPointerSignal,
                      child: GestureDetector(
                        onLongPress: _showImageMenu,
                        onSecondaryTap: _showImageMenu,
                        child: PhotoViewGallery.builder(
                          backgroundDecoration:
                              const BoxDecoration(color: Colors.transparent),
                          scrollPhysics: const BouncingScrollPhysics(),
                          builder: (context, index) =>
                              PhotoViewGalleryPageOptions(
                            imageProvider: _providerFor(index),
                            controller: _controllers.putIfAbsent(
                                index, PhotoViewController.new),
                            scaleStateController: _scaleStates.putIfAbsent(
                                index, PhotoViewScaleStateController.new),
                            initialScale: PhotoViewComputedScale.contained,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 8,
                            heroAttributes:
                                PhotoViewHeroAttributes(tag: _imgList[index]),
                          ),
                          itemCount: _imgList.length,
                          loadingBuilder: (context, event) => Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                value: event?.expectedTotalBytes == null
                                    ? null
                                    : event!.cumulativeBytesLoaded /
                                        event.expectedTotalBytes!,
                              ),
                            ),
                          ),
                          pageController: _pageController,
                          onPageChanged: (index) =>
                              setState(() => _currentPage = index),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
}
