import 'dart:convert';

enum MediaContentType { feed, reply, article }

/// Shared gallery contract. The public backend handles ordinary still images.
class FeedMedia {
  const FeedMedia(
      {required this.sourceUrl,
      this.previewUrl,
      this.videoUrl,
      this.isLivePhoto = false,
      this.isHdr = false,
      this.contentId,
      this.contentType = MediaContentType.feed});
  final String sourceUrl;
  final String? previewUrl, videoUrl, contentId;
  final bool isLivePhoto, isHdr;
  final MediaContentType contentType;

  String get displayUrl {
    final uri = Uri.tryParse(sourceUrl);
    return uri?.host == 'image.coolapk.com' && uri?.scheme == 'http'
        ? uri!.replace(scheme: 'https').toString()
        : sourceUrl;
  }

  String get originalUrl => displayUrl;
  String get thumbnailUrl => previewUrl ?? displayUrl;
  String get galleryPreviewUrl => thumbnailUrl;
  List<String> get sdrHdUrls => const [];

  static FeedMedia fromUrl(String url,
          {String? contentId,
          MediaContentType contentType = MediaContentType.feed}) =>
      FeedMedia(sourceUrl: url, contentId: contentId, contentType: contentType);

  static List<FeedMedia> fromContent(
      {Object? metadata,
      List<String>? urls,
      String? contentId,
      MediaContentType contentType = MediaContentType.feed}) {
    final values = urls?.isNotEmpty == true ? urls! : _urls(metadata);
    return [
      for (final url in values)
        if (url.isNotEmpty)
          fromUrl(url, contentId: contentId, contentType: contentType)
    ];
  }
}

List<String> _urls(Object? value, [int depth = 0]) {
  if (value == null || depth > 8) return [];
  if (value is String) {
    final text = value.trim();
    if (text.startsWith('[') || text.startsWith('{')) {
      try {
        return _urls(jsonDecode(text), depth + 1);
      } on FormatException {
        return [];
      }
    }
    final uri = Uri.tryParse(text);
    return uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty
        ? [text]
        : [];
  }
  if (value is List)
    return [for (final item in value) ..._urls(item, depth + 1)];
  if (value is Map) {
    for (final key in [
      'url',
      'uri',
      'pic',
      'imageUrl',
      'image_url',
      'sourceUrl'
    ]) {
      final result = _urls(value[key], depth + 1);
      if (result.isNotEmpty) return result;
    }
    for (final key in [
      'imageUriList',
      'image_uri_list',
      'pics',
      'picArr',
      'data'
    ]) {
      final result = _urls(value[key], depth + 1);
      if (result.isNotEmpty) return result;
    }
  }
  return [];
}

Object? readFeedMediaMetadata(Map json, String key) =>
    json[key] ?? json['image_uri_list'] ?? json['pics'];

Object? readFeedMediaUrls(Map json, String key) =>
    json[key] ?? readFeedMediaMetadata(json, 'imageUriList');

List<String>? feedMediaUrlsFromJson(Object? value) =>
    value == null ? null : _urls(value);
