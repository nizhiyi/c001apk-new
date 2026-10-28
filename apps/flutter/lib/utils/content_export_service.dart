import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../logic/model/feed/datum.dart';
import '../logic/model/feed_article/feed_article.dart';
import '../logic/network/network_repo.dart';
import '../logic/state/loading_state.dart';
import '../logic/content_filter/content_filter_projection.dart';
import '../logic/content_filter/content_filter_rule.dart';
import 'content_export.dart';
import 'storage_util.dart';

enum ExportFormat { markdown, html }

class PreparedExport {
  const PreparedExport(
      this.fileName, this.bytes, this.warnings, this.commentIds);
  final String fileName;
  final Uint8List bytes;
  final List<String> warnings;
  final List<String> commentIds;
}

class ExportCancelled implements Exception {}

/// Owns one export. No response is written back to the feed controller.
class ContentExportService {
  ContentExportService({
    Future<LoadingState> Function(String)? loadPopular,
    Set<String> Function()? blockedUids,
    Future<Uint8List?> Function(String)? loadImage,
    Future<bool> Function(String, Uint8List)? saveBytes,
  })  : _loadPopular = loadPopular ?? _popular,
        _blockedUids = blockedUids ?? _blocked,
        _imageOverride = loadImage,
        _saveBytes = saveBytes ?? _save;

  final Future<LoadingState> Function(String) _loadPopular;
  final Set<String> Function() _blockedUids;
  final Future<Uint8List?> Function(String)? _imageOverride;
  final Future<bool> Function(String, Uint8List) _saveBytes;
  final _cancel = CancelToken();
  static const maxImageBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 32 * 1024 * 1024;
  static const maxImages = 60;

  void cancel() => _cancel.cancel();
  void _check() {
    if (_cancel.isCancelled) throw ExportCancelled();
  }

  static Set<String> _blocked() => Set<String>.from(GStorage.blackList
      .get(BlackListBoxKey.userBlackList, defaultValue: <String>[]));

  static Future<LoadingState> _popular(String id) => NetworkRepo.getFeedReply(
      id: id,
      listType: 'popular',
      page: 1,
      firstItem: null,
      lastItem: null,
      discussMode: 1,
      feedType: 'feed',
      blockStatus: 0,
      fromFeedAuthor: 0,
      verify: false);

  Future<PreparedExport> prepare(Datum feed,
      {List<FeedArticle> articles = const [],
      required ExportFormat format}) async {
    _check();
    final warnings = <String>[];
    final notices = <String>[];
    var popular = <Datum>[];
    try {
      final result = await _loadPopular('${feed.id}');
      _check();
      if (result is Success) {
        popular = List<Datum>.from(result.response as List);
      } else if (result is! Empty) {
        notices.add('未能取得热门评论；可返回评论区完成验证后重试。本文件仅含已取得的置顶评论。');
        warnings.add('热门评论读取失败，本次无法保证保存前三条评论。');
      }
    } on ExportCancelled {
      rethrow;
    } catch (_) {
      notices.add('未能取得热门评论，本文件仅含已取得的置顶评论。');
      warnings.add('热门评论读取失败，本次无法保证保存前三条评论。');
    }
    _check();
    // Clone the pin marker: exporting must never mutate the live detail model.
    final pinned = (feed.topReplyRows ?? <Datum>[])
        .map((reply) => snapshotExportFeed(reply)..isTop = 1)
        .toList();
    bool allowed(Datum item) =>
        ContentFilterProjection.match(item, scope: FilterScope.comment) == null;
    final comments = selectExportComments(
            pinned.where(allowed).toList(), popular.where(allowed).toList(),
            blockedUids: _blockedUids())
        .map((item) => ContentFilterProjection.exportCopy(item,
            scope: FilterScope.comment))
        .toList();
    final safeFeed =
        ContentFilterProjection.exportCopy(feed, scope: FilterScope.feed);
    final safeArticles =
        ContentFilterProjection.match(feed, scope: FilterScope.feed) != null
            ? <FeedArticle>[]
            : articles
                .map((part) => FeedArticle.fromJson(part.toJson())
                  ..message =
                      ContentFilterProjection.sanitizeQuotes(part.message ?? '')
                  ..title =
                      ContentFilterProjection.sanitizeQuotes(part.title ?? '')
                  ..description = ContentFilterProjection.sanitizeQuotes(
                      part.description ?? ''))
                .toList();
    var doc = ExportDocument.fromFeed(safeFeed,
        articles: safeArticles, comments: comments, notices: notices);
    if (format == ExportFormat.markdown) {
      if (doc.imageUrls.isNotEmpty) {
        notices.add('Markdown 图片保留在线链接，离线阅读图片请另存为 HTML。');
        doc = ExportDocument.fromFeed(safeFeed,
            articles: safeArticles, comments: comments, notices: notices);
      }
      return PreparedExport(
          '${doc.fileName}.md',
          Uint8List.fromList(utf8.encode(doc.markdown)),
          warnings,
          comments.map((e) => '${e.id}').toList());
    }
    final images = <String, String>{};
    var bytesUsed = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    final urls = doc.imageUrls;
    for (final url in urls.take(maxImages)) {
      _check();
      if (DateTime.now().isAfter(deadline) || bytesUsed >= maxTotalBytes) break;
      try {
        final bytes = await (_imageOverride?.call(url) ?? _loadImage(url))
            .timeout(const Duration(seconds: 8));
        _check();
        final mime = bytes == null ? null : _imageMime(bytes);
        if (bytes == null ||
            mime == null ||
            bytes.length > maxImageBytes ||
            bytesUsed + bytes.length > maxTotalBytes) {
          continue;
        }
        if (!await _decodes(bytes)) continue;
        _check();
        bytesUsed += bytes.length;
        images[url] = 'data:$mime;base64,${base64Encode(bytes)}';
      } on ExportCancelled {
        rethrow;
      } catch (_) {/* Missing images are explicitly confirmed by the user. */}
    }
    _check();
    final missing = urls.length - images.length;
    if (missing > 0) {
      warnings.add('$missing 张图片未能保存，将以来源链接代替；这些图片无法离线查看。');
    }
    return PreparedExport(
        '${doc.fileName}.html',
        Uint8List.fromList(utf8.encode(doc.offlineHtml(images))),
        warnings,
        comments.map((e) => '${e.id}').toList());
  }

  Future<bool> save(PreparedExport prepared) async {
    _check();
    return _saveBytes(prepared.fileName, prepared.bytes);
  }

  Future<Uint8List?> _loadImage(String url) async {
    final cached = await DefaultCacheManager().getFileFromCache(url);
    _check();
    if (cached != null &&
        await cached.file.exists() &&
        await cached.file.length() <= maxImageBytes) {
      return cached.file.readAsBytes();
    }
    // A dedicated client intentionally has no account, protocol or cookie hooks.
    final client = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        followRedirects: false));
    try {
      final response = await client.get<ResponseBody>(url,
          options: Options(responseType: ResponseType.stream),
          cancelToken: _cancel);
      if (response.statusCode != 200 || response.data == null) return null;
      final length =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (length != null && length > maxImageBytes) return null;
      final result = BytesBuilder(copy: false);
      await for (final chunk in response.data!.stream) {
        _check();
        if (result.length + chunk.length > maxImageBytes) return null;
        result.add(chunk);
      }
      return result.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static String? _imageMime(Uint8List data) {
    bool starts(List<int> signature) =>
        data.length >= signature.length &&
        List.generate(signature.length, (i) => data[i] == signature[i])
            .every((e) => e);
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts([255, 216, 255])) return 'image/jpeg';
    if (starts([71, 73, 70, 56, 55, 97]) || starts([71, 73, 70, 56, 57, 97])) {
      return 'image/gif';
    }
    if (data.length >= 12 &&
        ascii.decode(data.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(data.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  static Future<bool> _decodes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 32 * 1024 * 1024) return false;
      codec =
          await descriptor.instantiateCodec(targetWidth: 1, targetHeight: 1);
      image = (await codec.getNextFrame()).image;
      return true;
    } catch (_) {
      return false;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Future<bool> _save(String name, Uint8List bytes) async {
    final ext = name.endsWith('.md') ? 'md' : 'html';
    final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存内容',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: bytes,
        lockParentWindow: Platform.isWindows);
    if (path == null) return false;
    // file_picker 8.1.1 writes mobile bytes itself; its desktop saver only
    // returns the chosen path. Keep this aligned with the locked dependency.
    if (!(Platform.isAndroid || Platform.isIOS)) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return true;
  }
}
