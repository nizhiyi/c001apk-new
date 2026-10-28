/// Stored values identify the effect, preserving existing choices on upgrade.
enum LiquidGlassLevel {
  low('minimal', '低档', '轻量通透，不使用实时模糊与折射'),
  medium('low', '中档', '柔光轮廓，图标保持清晰'),
  high('medium', '高档', '通透边缘，图标随滑块折射'),
  complete('high', '完全', '平时无边，按住后边缘微光');

  const LiquidGlassLevel(this.storedValue, this.label, this.description);

  final String storedValue;
  final String label;
  final String description;
  bool get usesBackdrop => this != low;
  bool get refractsContent => this == high || this == complete;

  static LiquidGlassLevel fromStored(Object? value) {
    for (final level in values) {
      if (level.storedValue == value) return level;
    }
    return medium;
  }
}
