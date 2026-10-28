import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'content_filter_rule.dart';

class ContentFilterEngine {
  ContentFilterEngine(FilterRuleSet ruleSet)
      : _rules = FilterRuleSet.fromJson(ruleSet.toJson())
            .rules
            .map(_CompiledRule.new)
            .toList(growable: false);
  final List<_CompiledRule> _rules;

  FilterMatch? evaluate(
    FilterInput input, {
    FilterLevel level = FilterLevel.standard,
    Set<String> disabledRuleIds = const {},
    Set<String> allowedAuthorUids = const {},
    Set<String> allowedContentKeys = const {},
  }) {
    if ((input.authorUid != null &&
            allowedAuthorUids.contains(input.authorUid)) ||
        (input.contentKey != null &&
            allowedContentKeys.contains(input.contentKey))) {
      return null;
    }
    String? text;
    for (final compiled in _rules) {
      final rule = compiled.rule;
      if (!rule.scopes.contains(input.scope) ||
          disabledRuleIds.contains(rule.id) ||
          (rule.kind == FilterRuleKind.text &&
              rule.level.index > level.index)) {
        continue;
      }
      final bool matched;
      switch (rule.kind) {
        case FilterRuleKind.author:
          matched =
              input.authorUid != null && rule.values.contains(input.authorUid);
        case FilterRuleKind.topic:
          matched = rule.values.any((value) =>
              input.topicIds.contains(value) ||
              input.topicNames.contains(value));
        case FilterRuleKind.text:
          text ??= _maskExcludedTerms(visibleFilterText(input.text));
          matched = _matchesText(text, compiled);
      }
      if (matched) {
        return FilterMatch(rule.id, rule.reason, rule.kind);
      }
    }
    return null;
  }
}

/// Excludes URLs/attributes, script/style contents and invisible elements.
String visibleFilterText(String source) {
  final fragment = html.parseFragment(source);
  final buffer = StringBuffer();
  void visit(Node node) {
    if (node is Text) {
      buffer.write(node.data);
    } else if (node is Element) {
      if (const {'script', 'style', 'template', 'noscript'}
              .contains(node.localName) ||
          node.attributes.containsKey('hidden') ||
          node.attributes['aria-hidden'] == 'true') {
        return;
      }
      final block = const {
        'p',
        'div',
        'br',
        'li',
        'blockquote',
        'section',
        'h1',
        'h2',
        'h3'
      }.contains(node.localName);
      if (block) {
        buffer.write('\n');
      }
      for (final child in node.nodes) {
        visit(child);
      }
      if (block) {
        buffer.write('\n');
      }
    } else {
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  visit(fragment);
  // Keep boundaries until matching, so an exception cannot exempt another sentence.
  return buffer
      .toString()
      .split(RegExp(r'[\r\n]+'))
      .map(normalizeFilterText)
      .join('\n');
}

class _CompiledRule {
  _CompiledRule(this.rule)
      : groups = rule.groups
            .map((group) => group.map(normalizeFilterText).toList())
            .toList(growable: false),
        exceptions =
            rule.exceptions.map(normalizeFilterText).toList(growable: false);
  final FilterRule rule;
  final List<List<String>> groups;
  final List<String> exceptions;
}

String _maskExcludedTerms(String text) {
  for (final excluded in excludedFilterTerms) {
    // Preserve positions and never join the two sides into a new phrase.
    text = text.replaceAll(excluded, ' ' * excluded.length);
  }
  return text;
}

bool _matchesText(String text, _CompiledRule compiled) {
  final groups = compiled.groups;
  final exceptions = compiled.exceptions;
  final distance = compiled.rule.maxDistance;
  for (final sentence in text.split(RegExp(r'[。！？!?；;\r\n]+'))) {
    if (sentence.isEmpty) {
      continue;
    }
    // An exception is confined to this sentence, never to the entire post.
    if (exceptions.any(sentence.contains)) {
      continue;
    }
    if (groups.any((group) => !group.any(sentence.contains))) {
      continue;
    }
    final occurrences = <({int start, int end, int group})>[];
    for (var group = 0; group < groups.length; group++) {
      for (final term in groups[group]) {
        var offset = 0;
        while (offset < sentence.length) {
          final index = sentence.indexOf(term, offset);
          if (index < 0) {
            break;
          }
          occurrences
              .add((start: index, end: index + term.length, group: group));
          offset = index + 1;
        }
      }
    }
    occurrences.sort((a, b) => a.end.compareTo(b.end));
    // For each endpoint, the latest start in every group gives the smallest
    // possible common window. Each event is processed once, at most 8 groups.
    final latestStarts = List<int>.filled(groups.length, -1);
    for (final hit in occurrences) {
      if (hit.start > latestStarts[hit.group]) {
        latestStarts[hit.group] = hit.start;
      }
      var earliest = latestStarts.first;
      for (final start in latestStarts.skip(1)) {
        if (start < earliest) {
          earliest = start;
        }
      }
      if (earliest >= 0 && hit.end - earliest <= distance) {
        return true;
      }
    }
  }
  return false;
}
