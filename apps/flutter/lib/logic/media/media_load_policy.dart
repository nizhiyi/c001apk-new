import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Ordinary-image builds never perform automatic native media loading.
class MediaLoadPolicy extends ValueNotifier<bool> {
  MediaLoadPolicy(Box<dynamic> settings) : super(false);
  static MediaLoadPolicy? current;
  void start() {}
  Future<void> refresh() async {}
  @override
  void dispose() {
    if (identical(current, this)) current = null;
    super.dispose();
  }
}
