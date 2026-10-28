enum FilterLevel { standard, strict }

enum FilterScope { feed, comment, user }

enum FilterRuleKind { author, topic, text }

/// The caller supplies only this item's author and visible content.
class FilterInput {
  const FilterInput(
      {required this.scope,
      this.id,
      this.authorUid,
      this.text = '',
      this.topicIds = const {},
      this.topicNames = const {}});
  final FilterScope scope;
  final String? id;
  final String? authorUid;
  final String text;
  final Set<String> topicIds;
  final Set<String> topicNames;
  String? get contentKey => id == null ? null : '${scope.name}:$id';
}

class FilterMatch {
  const FilterMatch(this.ruleId, this.reason, this.kind);
  final String ruleId;
  final String reason;
  final FilterRuleKind kind;
}

/// No regex supplied by subscriptions is ever executed.
class FilterRule {
  const FilterRule(
      {required this.id,
      required this.reason,
      required this.kind,
      this.level = FilterLevel.standard,
      this.scopes = const {
        FilterScope.feed,
        FilterScope.comment,
        FilterScope.user
      },
      this.values = const [],
      this.groups = const [],
      this.maxDistance = 80,
      this.exceptions = const [],
      this.reviewedAt,
      this.sources = const []});
  final String id;
  final String reason;
  final FilterRuleKind kind;
  final FilterLevel level;
  final Set<FilterScope> scopes;
  final List<String> values;
  final List<List<String>> groups;

  /// Maximum span, including all matching terms, in normalized UTF-16 units.
  final int maxDistance;
  final List<String> exceptions;
  final DateTime? reviewedAt;
  final List<String> sources;

  Map<String, dynamic> toJson() => {
        'id': id,
        'reason': reason,
        'kind': kind.name,
        'level': level.name,
        'scopes': scopes.map((e) => e.name).toList(),
        'values': values,
        'groups': groups,
        'maxDistance': maxDistance,
        'exceptions': exceptions,
        if (reviewedAt != null)
          'reviewedAt': reviewedAt!.toUtc().toIso8601String(),
        'sources': sources,
      };

  factory FilterRule.fromJson(Map<dynamic, dynamic> json) {
    _keys(json, {
      'id',
      'reason',
      'kind',
      'level',
      'scopes',
      'values',
      'groups',
      'maxDistance',
      'exceptions',
      'reviewedAt',
      'sources'
    });
    final id = _string(json['id'], 100);
    if (!RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(id)) {
      _invalid();
    }
    final kind = _enum(json['kind'], FilterRuleKind.values);
    final level = _enum(json['level'] ?? 'standard', FilterLevel.values);
    final rawScopes = json['scopes'] ?? ['feed', 'comment', 'user'];
    if (rawScopes is! List || rawScopes.isEmpty || rawScopes.length > 3) {
      _invalid();
    }
    final scopes = rawScopes.map((e) => _enum(e, FilterScope.values)).toSet();
    if (scopes.length != rawScopes.length) {
      _invalid();
    }
    final values = _strings(json['values'] ?? [], 200, 256);
    final exceptions = _strings(json['exceptions'] ?? [], 16, 128);
    final rawGroups = json['groups'] ?? [];
    if (rawGroups is! List || rawGroups.length > 8) {
      _invalid();
    }
    final groups = rawGroups.map((e) => _strings(e, 16, 256)).toList();
    final distance = json['maxDistance'] ?? 80;
    if (distance is! int || distance < 1 || distance > 240) {
      _invalid();
    }
    if (kind == FilterRuleKind.text) {
      if (groups.isEmpty || groups.any((e) => e.isEmpty) || values.isNotEmpty) {
        _invalid();
      }
      for (final term in groups.expand((e) => e)) {
        final normalized = normalizeFilterText(term);
        if (normalized.isEmpty ||
            excludedFilterTerms.any(normalized.contains)) {
          _invalid();
        }
      }
    } else {
      if (values.isEmpty || groups.isNotEmpty || exceptions.isNotEmpty) {
        _invalid();
      }
      if (kind == FilterRuleKind.author &&
          values.any((e) => !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(e))) {
        _invalid();
      }
      if (level != FilterLevel.standard) {
        _invalid();
      }
    }
    final sources = _strings(json['sources'] ?? [], 8, 2048);
    for (final source in sources) {
      final uri = Uri.tryParse(source);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        _invalid();
      }
    }
    return FilterRule(
        id: id,
        reason: _string(json['reason'], 200),
        kind: kind,
        level: level,
        scopes: Set.unmodifiable(scopes),
        values: List.unmodifiable(values),
        groups:
            List.unmodifiable(groups.map((e) => List<String>.unmodifiable(e))),
        maxDistance: distance,
        exceptions: List.unmodifiable(exceptions),
        reviewedAt:
            json['reviewedAt'] == null ? null : _date(json['reviewedAt']),
        sources: List.unmodifiable(sources));
  }
}

class FilterRuleSet {
  const FilterRuleSet(
      {this.schemaVersion = 1,
      required this.revision,
      required this.publishedAt,
      required this.rules});
  final int schemaVersion;
  final int revision;
  final DateTime publishedAt;
  final List<FilterRule> rules;
  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'revision': revision,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'rules': rules.map((e) => e.toJson()).toList()
      };
  factory FilterRuleSet.fromJson(Map<dynamic, dynamic> json) {
    _keys(json, {'schemaVersion', 'revision', 'publishedAt', 'rules'});
    if (json['schemaVersion'] != 1 || json['schemaVersion'] is! int) {
      _invalid();
    }
    final revision = json['revision'];
    if (revision is! int || revision < 1 || revision > 2147483647) {
      _invalid();
    }
    final raw = json['rules'];
    if (raw is! List || raw.length > 2000) {
      _invalid();
    }
    final rules = <FilterRule>[];
    final ids = <String>{};
    for (final entry in raw) {
      if (entry is! Map) {
        _invalid();
      }
      final rule = FilterRule.fromJson(entry);
      if (!ids.add(rule.id)) {
        _invalid();
      }
      rules.add(rule);
    }
    return FilterRuleSet(
        revision: revision,
        publishedAt: _date(json['publishedAt']),
        rules: List.unmodifiable(rules));
  }
}

const excludedFilterTerms = ['lsp', '手冲', '后入', '性压抑'];

/// Full-width ASCII, case, whitespace and invisible separator normalization.
String normalizeFilterText(String value) =>
    String.fromCharCodes(value.runes.map((r) =>
            r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : (r == 0x3000 ? 32 : r)))
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200b-\u200f\u202a-\u202e\u2060\ufeff]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

Never _invalid() => throw const FormatException('内容过滤规则格式无效');
void _keys(Map<dynamic, dynamic> map, Set<String> allowed) {
  if (map.keys.any((key) => key is! String || !allowed.contains(key))) {
    _invalid();
  }
}

String _string(dynamic value, int max) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _invalid();
  }
  return value;
}

List<String> _strings(dynamic value, int maxCount, int maxLength) {
  if (value is! List || value.length > maxCount) {
    _invalid();
  }
  final result = value.map((e) => _string(e, maxLength)).toList();
  if (result.toSet().length != result.length) {
    _invalid();
  }
  return result;
}

T _enum<T extends Enum>(dynamic value, List<T> values) {
  for (final entry in values) {
    if (entry.name == value) {
      return entry;
    }
  }
  _invalid();
}

DateTime _date(dynamic value) {
  if (value is! String ||
      value.length > 40 ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$')
          .hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    _invalid();
  }
  // DateTime.parse otherwise silently accepts e.g. February 31.
  final datePart = value.substring(0, 10);
  final parts = datePart.split('-').map(int.parse).toList();
  final checked = DateTime.utc(parts[0], parts[1], parts[2]);
  if (checked.year != parts[0] ||
      checked.month != parts[1] ||
      checked.day != parts[2] ||
      int.parse(value.substring(11, 13)) > 23 ||
      int.parse(value.substring(14, 16)) > 59 ||
      int.parse(value.substring(17, 19)) > 59) {
    _invalid();
  }
  return parsed.toUtc();
}
