enum MediaAutoLoadMode {
  off('off', '关闭'),
  wifi('wifi', 'WiFi下'),
  always('always', '总是');

  const MediaAutoLoadMode(this.storedValue, this.label);

  static const storageKey = 'mediaAutoLoad';

  final String storedValue;
  final String label;

  static MediaAutoLoadMode fromStored(Object? value) {
    for (final mode in values) {
      if (mode.storedValue == value) return mode;
    }
    return wifi;
  }
}
