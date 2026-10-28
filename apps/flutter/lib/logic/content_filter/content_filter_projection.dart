import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:hive/hive.dart';

import '../model/feed/datum.dart';
import '../../utils/storage_util.dart';
import 'app_content_filter.dart';
import 'content_filter_rule.dart';

/// Adapts only the current item's content. Replies and forwards are separate.
class ContentFilterProjection {
  static FilterScope? scopeOf(Datum data) => switch (data.entityType) {
        'feed' || 'topic' => FilterScope.feed,
        'feed_reply' => FilterScope.comment,
        'user' || 'contacts' => FilterScope.user,
        _ => null,
      };

  static String keyOf(Datum data, {FilterScope? scope}) =>
      '${(scope ?? scopeOf(data) ?? FilterScope.feed).name}:${data.id ?? data.entityId ?? data.uid ?? identityHashCode(data)}';

  static String _withoutQuotes(String text) {
    final fragment = html.parseFragment(_mapMarkdownQuotes(text, (_) => '\n'));
    for (final quote in fragment.querySelectorAll('blockquote, .feed-quote')) {
      quote.remove();
    }
    return fragment.outerHtml.replaceAll(
        RegExp(r'\[quote(?:=[^\]]*)?\][\s\S]*?\[/quote\]',
            caseSensitive: false),
        '');
  }

  static String _mapMarkdownQuotes(
          String text, String Function(String) transform) =>
      text.replaceAllMapped(
          RegExp(r'^(?: {0,3}>[^\r\n]*(?:\r?\n|$))+', multiLine: true),
          (match) => transform(match[0]!));

  static FilterInput inputOf(Datum data, {FilterScope? scope}) {
    final ids = <String>{};
    final names = <String>{};
    void topic(dynamic id, String? name, String? url, String? type) {
      if (type != 'topic' && !(url?.contains('/t/') ?? false)) return;
      if (id != null) ids.add('$id');
      if (name?.isNotEmpty == true) names.add(name!);
    }

    for (final row in data.relationRows ?? []) {
      topic(row.id, row.title, row.url, row.entityType);
    }
    final target = data.targetRow;
    if (target != null) {
      topic(target.id, target.title, target.url, target.entityType);
    }
    if (data.entityType == 'topic') {
      topic(data.id, data.title, data.url, 'topic');
    }
    names.addAll((data.tags ?? '')
        .split(RegExp(r'[,，#]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty));
    if (data.ttitle?.isNotEmpty == true) names.add(data.ttitle!);
    final own = _withoutQuotes(data.message ?? '');
    // Explicit topic links, not arbitrary substring matches or user mentions.
    for (final anchor in html.parseFragment(own).querySelectorAll('a[href]')) {
      final uri = Uri.tryParse(anchor.attributes['href'] ?? '');
      if (uri == null ||
          (uri.hasAuthority &&
              !const {'coolapk.com', 'www.coolapk.com', 'm.coolapk.com'}
                  .contains(uri.host))) {
        continue;
      }
      if (uri.path.startsWith('/t/')) {
        final tag = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
        names.add(tag);
        names.add(anchor.text.replaceAll('#', '').trim());
      }
    }
    var article = '';
    try {
      final raw = jsonDecode(data.messageRawOutput ?? 'null');
      if (raw is List) {
        article = raw
            .whereType<Map>()
            .where((e) => const {'text', 'title', 'image', 'shareUrl'}
                .contains(e['type']))
            .map((e) => _withoutQuotes(
                '${e['message'] ?? ''}\n${e['title'] ?? ''}\n${e['description'] ?? ''}'))
            .join('\n');
      }
    } on FormatException {
      /* Malformed article is handled by its existing parser. */
    }
    final actualScope = scope ?? scopeOf(data) ?? FilterScope.feed;
    return FilterInput(
        scope: actualScope,
        id: '${data.id ?? data.entityId ?? ''}',
        authorUid:
            '${data.uid ?? (actualScope == FilterScope.user ? data.id : '')}',
        text: '${data.messageTitle ?? ''}\n${data.title ?? ''}\n$own\n$article',
        topicIds: ids,
        topicNames: names);
  }

  static FilterMatch? legacyMatch(Datum data) {
    if (!Hive.isBoxOpen('blackList')) return null;
    final users = GStorage.blackList
        .get(BlackListBoxKey.userBlackList, defaultValue: <String>[]) as List;
    if (users.contains('${data.uid}')) {
      return FilterMatch(
          'legacy.user:${data.uid}', '个人用户黑名单', FilterRuleKind.author);
    }
    final topics = GStorage.blackList
        .get(BlackListBoxKey.topicBlackList, defaultValue: <String>[]) as List;
    final text =
        '${data.tags},${data.ttitle},${data.relationRows?.firstOrNull?.title}';
    for (final keyword in topics.whereType<String>()) {
      if (keyword.isNotEmpty && text.contains(keyword)) {
        return FilterMatch(
            'legacy.topic:$keyword', '个人话题黑名单：$keyword', FilterRuleKind.topic);
      }
    }
    return null;
  }

  static FilterMatch? match(Datum data, {FilterScope? scope}) {
    final legacy = legacyMatch(data);
    if (legacy != null) return legacy;
    final actualScope = scope ?? scopeOf(data);
    if (actualScope == null) return null;
    return AppContentFilter.service
        ?.evaluate(inputOf(data, scope: actualScope));
  }

  static String displayMessage(Datum data) =>
      sanitizeQuotes(data.message ?? '');

  static String sanitizeQuotes(String source) {
    final service = AppContentFilter.service;
    if (service == null || !service.enabled) return source;
    bool matchesQuote(String text) {
      // Every level inside this container is quoted material. Do not discard
      // its nested quotation again before deciding whether to redact it.
      final flattened = text
          .replaceAll(RegExp(r'^(?: {0,3}> ?)+', multiLine: true), '')
          .replaceAll(
              RegExp(r'\[/?quote(?:=[^\]]*)?\]', caseSensitive: false), '\n');
      final tree = html.parseFragment(flattened);
      for (final nested in tree.querySelectorAll('blockquote, .feed-quote')) {
        nested.replaceWith(
            dom.Element.tag('div')..nodes.addAll(nested.nodes.toList()));
      }
      return service.evaluate(inputOf(
              Datum(entityType: 'feed_reply', message: tree.outerHtml),
              scope: FilterScope.comment)) !=
          null;
    }

    final markdown = _mapMarkdownQuotes(source, (quote) {
      final content = quote
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^ {0,3}> ?'), ''))
          .join('\n');
      return matchesQuote(content) ? '> 引用内容已过滤\n' : quote;
    });
    final fragment = html.parseFragment(markdown);
    var changed = false;
    for (final quote in fragment.querySelectorAll('blockquote, .feed-quote')) {
      if (matchesQuote(quote.innerHtml)) {
        quote.nodes.clear();
        quote.text = '引用内容已过滤';
        changed = true;
      }
    }
    var result = changed ? fragment.outerHtml : markdown;
    result = result.replaceAllMapped(
        RegExp(r'\[quote(?:=[^\]]*)?\]([\s\S]*?)\[/quote\]',
            caseSensitive: false),
        (m) => matchesQuote(m[1]!) ? '引用内容已过滤' : m[0]!);
    return result;
  }

  /// A detached export projection, preserving reply relationships without text leaks.
  static Datum exportCopy(Datum data, {FilterScope? scope}) {
    final copy =
        Datum.fromJson(jsonDecode(jsonEncode(data)) as Map<String, dynamic>);
    // Preserve the flag explicitly across legacy isTop and API is_top records.
    copy.isTop = data.isTop;
    void project(Datum item, FilterScope? forced, int depth) {
      if (depth > 20) {
        item.message = '引用层级过深';
        item.replyRows = null;
        item.forwardSourceFeed = null;
        return;
      }
      if (match(item, scope: forced) != null) {
        item.message = '内容已过滤';
        item.messageTitle = null;
        item.title = null;
        item.messageRawOutput = null;
        item.picArr = null;
        item.imageUriList = null;
        item.pic = null;
        item.messageCover = null;
        item.extraUrl = null;
        item.extraPic = null;
        item.extraTitle = null;
        item.forwardSourceFeed = null;
        item.sourceFeed = null;
        item.feed = null;
      } else {
        item.message = displayMessage(item);
        try {
          final raw = jsonDecode(item.messageRawOutput ?? 'null');
          if (raw is List) {
            for (final part in raw.whereType<Map>()) {
              for (final field in ['message', 'title', 'description']) {
                if (part[field] is String) {
                  part[field] = sanitizeQuotes(part[field] as String);
                }
              }
            }
            item.messageRawOutput = jsonEncode(raw);
          }
        } on FormatException {
          /* Preserve the existing malformed-article fallback. */
        }
      }
      for (final child in [
        ...?item.replyRows,
        ...?item.topReplyRows,
        ...?item.replyMeRows
      ]) {
        project(child, FilterScope.comment, depth + 1);
      }
      if (item.forwardSourceFeed != null) {
        project(item.forwardSourceFeed!, FilterScope.feed, depth + 1);
      }
      for (final field in ['sourceFeed', 'feed']) {
        final value = field == 'feed' ? item.feed : item.sourceFeed;
        if (value is Map<String, dynamic>) {
          final nested = Datum.fromJson(value);
          project(nested, FilterScope.feed, depth + 1);
          final json = jsonDecode(jsonEncode(nested));
          if (field == 'feed') {
            item.feed = json;
          } else {
            item.sourceFeed = json;
          }
        }
      }
    }

    project(copy, scope, 0);
    return copy;
  }
}
