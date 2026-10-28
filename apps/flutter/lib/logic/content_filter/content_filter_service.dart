import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'builtin_filter_rules.dart';
import 'content_filter_engine.dart';
import 'content_filter_rule.dart';

class ContentFilterService extends ChangeNotifier {
  ContentFilterService(this._box, {Dio? dio, DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            followRedirects: false,
            responseType: ResponseType.stream,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'c001apk-content-filter/1'
            })) {
    // Reuse only an injected transport. No account headers, cookies, interceptors,
    // transformer, base URL or request defaults can enter this client.
    if (dio != null) {
      _dio.httpClientAdapter = dio.httpClientAdapter;
    }
    _enabled = _box.get('enabled') == true;
    _level = _box.get('level') == 'strict'
        ? FilterLevel.strict
        : FilterLevel.standard;
    _disabledRuleIds = _readSet('disabledRuleIds');
    _disabledListKinds =
        _readSet('disabledListKinds').intersection({'author', 'topic'});
    _allowedAuthorUids = _readSet('allowedAuthorUids');
    _allowedContentKeys = _readSet('allowedContentKeys');
    final checked = _box.get('lastCheckedAt');
    if (checked is String) {
      _lastCheckedAt = DateTime.tryParse(checked)?.toUtc();
    }
    _ruleSet = FilterRuleSet.fromJson(_ruleSet.toJson());
    try {
      final cached = _box.get('ruleSet');
      if (cached is Map) {
        final parsed = _subscription(cached);
        if (parsed.revision >= _ruleSet.revision) {
          _ruleSet = parsed;
        }
      }
    } on FormatException {
      _updateMessage = '规则缓存损坏，已使用内置规则';
    }
    final personal = _box.get('personalRules');
    if (personal is List && personal.length <= 200) {
      final ids = <String>{};
      for (final raw in personal) {
        try {
          if (raw is! Map) {
            continue;
          }
          final rule = FilterRule.fromJson(raw);
          if (!rule.id.startsWith('personal.')) continue;
          if (ids.add(rule.id)) {
            _personalRules.add(rule);
          }
        } on FormatException {
          // Keep independent valid personal entries if one entry is damaged.
        }
      }
    }
    _rebuildEngines();
  }

  static const rulesUrl =
      'https://raw.githubusercontent.com/TG-Twilight/c001apk/filters/rules.json';
  static const maxDownloadBytes = 1024 * 1024;
  final Box<dynamic> _box;
  final Dio _dio;
  final DateTime Function() _now;
  bool _enabled = false;
  FilterLevel _level = FilterLevel.standard;
  FilterRuleSet _ruleSet = builtinFilterRules;
  DateTime? _lastCheckedAt;
  String? _updateMessage;
  bool _updating = false;
  bool _disposed = false;
  Set<String> _disabledRuleIds = {};
  Set<String> _disabledListKinds = {};
  Set<String> _allowedAuthorUids = {};
  Set<String> _allowedContentKeys = {};
  final List<FilterRule> _personalRules = [];
  late ContentFilterEngine _engine;
  late ContentFilterEngine _personalEngine;

  bool get enabled => _enabled;
  FilterLevel get level => _level;
  FilterRuleSet get ruleSet => _ruleSet;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get updateMessage => _updateMessage;
  bool get updating => _updating;
  Set<String> get disabledRuleIds => Set.unmodifiable(_disabledRuleIds);
  Set<String> get allowedAuthorUids => Set.unmodifiable(_allowedAuthorUids);
  Set<String> get allowedContentKeys => Set.unmodifiable(_allowedContentKeys);
  List<FilterRule> get personalRules => List.unmodifiable(_personalRules);

  // This is the category choice, independent of individual exceptions.
  bool isListEnabled(FilterRuleKind kind) =>
      !_disabledListKinds.contains(kind.name);

  Future<void> setListEnabled(FilterRuleKind kind, bool enabled) async {
    if (kind == FilterRuleKind.text) {
      throw ArgumentError.value(kind, 'kind', '仅支持用户或话题名单');
    }
    final disabledKinds = {..._disabledListKinds};
    final disabledIds = {..._disabledRuleIds};
    if (enabled) {
      disabledKinds.remove(kind.name);
      // An explicit group enable restores all current subscription entries.
      // Personal rules and unrelated individual choices remain independent.
      disabledIds.removeAll(_ruleSet.rules
          .where((rule) => rule.kind == kind)
          .map((rule) => rule.id));
    } else {
      disabledKinds.add(kind.name);
    }
    // Update the current choices before yielding so a second toggle merges
    // with this one instead of persisting an older snapshot.
    _disabledListKinds = disabledKinds;
    _disabledRuleIds = disabledIds;
    _rebuildEngines();
    await _box.putAll({
      'disabledListKinds': disabledKinds.toList(),
      'disabledRuleIds': disabledIds.toList(),
    });
    _notify();
  }

  Set<String> _readSet(String key) {
    final value = _box.get(key);
    if (value is! List || value.length > 10000) {
      return {};
    }
    return value
        .whereType<String>()
        .where((e) => e.isNotEmpty && e.length <= 200)
        .toSet();
  }

  FilterRuleSet _subscription(Map<dynamic, dynamic> json) {
    final rules = FilterRuleSet.fromJson(json);
    if (rules.rules.any((e) => e.id.startsWith('personal.'))) {
      throw const FormatException('订阅不能使用个人规则命名空间');
    }
    return rules;
  }

  void _rebuildEngines() {
    _engine = ContentFilterEngine(FilterRuleSet(
        schemaVersion: _ruleSet.schemaVersion,
        revision: _ruleSet.revision,
        publishedAt: _ruleSet.publishedAt,
        rules: _ruleSet.rules
            .where((rule) => !_disabledListKinds.contains(rule.kind.name))
            .toList()));
    _personalEngine = ContentFilterEngine(FilterRuleSet(
        revision: 1,
        publishedAt: DateTime.utc(2026, 10, 26),
        rules: _personalRules));
  }

  FilterMatch? evaluate(FilterInput input) {
    if (!_enabled) {
      return null;
    }
    FilterMatch? evaluateWith(ContentFilterEngine engine) =>
        engine.evaluate(input,
            level: _level,
            disabledRuleIds: _disabledRuleIds,
            allowedAuthorUids: _allowedAuthorUids,
            allowedContentKeys: _allowedContentKeys);
    return evaluateWith(_personalEngine) ?? evaluateWith(_engine);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _box.put('enabled', value);
    _notify();
    if (value) {
      await checkForUpdates();
    }
  }

  /// Saves onboarding's explicit changes before notifying. Subscription I/O
  /// runs independently so entering the app never waits on a rule download.
  Future<void> applyPreferences({bool? enabled, FilterLevel? level}) async {
    if (enabled == null && level == null) return;
    await _box.putAll({
      if (enabled != null) 'enabled': enabled,
      if (level != null) 'level': level.name,
    });
    await _box.flush();
    if (enabled != null) _enabled = enabled;
    if (level != null) _level = level;
    _notify();
    if (enabled == true) unawaited(checkForUpdates());
  }

  Future<void> setLevel(FilterLevel value) async {
    _level = value;
    await _box.put('level', value.name);
    _notify();
  }

  Future<void> setRuleDisabled(String id, bool value) =>
      _setChoice('disabledRuleIds', _disabledRuleIds, id, value);
  Future<void> setAuthorAllowed(String uid, bool value) =>
      _setChoice('allowedAuthorUids', _allowedAuthorUids, uid, value);
  Future<void> setContentAllowed(String key, bool value) =>
      _setChoice('allowedContentKeys', _allowedContentKeys, key, value);

  Future<void> _setChoice(
      String key, Set<String> choices, String value, bool add) async {
    if (value.isEmpty || value.length > 200) {
      throw const FormatException('例外内容无效');
    }
    if (add) {
      if (choices.length >= 10000 && !choices.contains(value)) {
        throw const FormatException('例外数量过多');
      }
      choices.add(value);
    } else {
      choices.remove(value);
    }
    await _box.put(key, choices.toList());
    _notify();
  }

  Future<void> addPersonalRule(FilterRule rule) async {
    final validated = FilterRule.fromJson(rule.toJson());
    if (!validated.id.startsWith('personal.') ||
        _personalRules.length >= 200 ||
        _personalRules.any((e) => e.id == validated.id) ||
        _ruleSet.rules.any((e) => e.id == validated.id)) {
      throw const FormatException('个人规则重复或数量过多');
    }
    _personalRules.add(validated);
    await _savePersonal();
  }

  Future<void> removePersonalRule(String id) async {
    _personalRules.removeWhere((rule) => rule.id == id);
    await _savePersonal();
  }

  Future<void> _savePersonal() async {
    await _box.put(
        'personalRules', _personalRules.map((e) => e.toJson()).toList());
    _rebuildEngines();
    _notify();
  }

  Future<void> checkForUpdates({bool force = false}) async {
    if (_disposed || _updating || (!force && !_enabled)) {
      return;
    }
    final now = _now().toUtc();
    if (!force &&
        _lastCheckedAt != null &&
        now.difference(_lastCheckedAt!) < const Duration(hours: 6)) {
      return;
    }
    _updating = true;
    _updateMessage = '正在检查规则更新';
    _notify();
    try {
      final response = await _dio.get<ResponseBody>(rulesUrl,
          options: Options(
              followRedirects: false,
              responseType: ResponseType.stream,
              validateStatus: (status) => status == 200));
      if (response.statusCode != 200 || response.data == null) {
        throw const FormatException();
      }
      final type =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
              '';
      if (!(type.startsWith('application/json') ||
          type.startsWith('text/plain'))) {
        throw const FormatException();
      }
      final declared = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '');
      if (declared != null && (declared < 0 || declared > maxDownloadBytes)) {
        throw const FormatException();
      }
      final bytes = <int>[];
      await for (final chunk
          in response.data!.stream.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > maxDownloadBytes) {
          throw const FormatException();
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException();
      }
      final candidate = _subscription(decoded);
      if (candidate.revision < _ruleSet.revision ||
          (candidate.revision == _ruleSet.revision &&
              jsonEncode(candidate.toJson()) !=
                  jsonEncode(_ruleSet.toJson()))) {
        throw const FormatException();
      }
      // Persist the whole validated subscription before exposing it. Never merge
      // removed rules or touch personal choices during an update.
      await _box.put('ruleSet', candidate.toJson());
      await _box.put('lastCheckedAt', now.toIso8601String());
      _ruleSet = candidate;
      _lastCheckedAt = now;
      _rebuildEngines();
      _updateMessage = '规则已是最新（版本 ${candidate.revision}）';
    } catch (_) {
      _updateMessage = '规则更新失败，继续使用已有规则';
    } finally {
      _updating = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
