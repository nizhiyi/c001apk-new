import 'package:flutter_test/flutter_test.dart';

import '../../tool/assemble_private_extensions.dart' as assembly;

void main() {
  test('overlay accepts implementation and regression paths', () {
    for (final path in [
      'apps/flutter/lib/components/liquid_glass_surface.dart',
      'apps/flutter/lib/logic/media/motion_photo.dart',
      'apps/flutter/android/app/src/main/kotlin/app/awavenue/c001apk/MediaBridge.kt',
      'apps/flutter/windows/runner/media_viewer.cpp',
      'apps/flutter/test/ui/imageview_hd_test.dart',
    ]) {
      expect(assembly.allowed(path), isTrue, reason: path);
    }
  });

  test('overlay rejects escapes, tooling, credentials and dependency changes',
      () {
    for (final path in [
      '../outside.dart',
      '/apps/flutter/lib/components/liquid_glass_surface.dart',
      'apps/flutter/lib/logic/media/../main.dart',
      r'apps\flutter\lib\logic\media\motion_photo.dart',
      'apps/flutter//lib/logic/media/motion_photo.dart',
      'apps/flutter/pubspec.yaml',
      'apps/flutter/pubspec.lock',
      'apps/flutter/android/key.properties',
      'apps/flutter/tool/assemble_private_extensions.dart',
      '.github/workflows/build.yml',
    ]) {
      expect(assembly.allowed(path), isFalse, reason: path);
    }
  });

  test('directory containment requires a complete directory boundary', () {
    expect(assembly.within('/project/.local/app', '/project/.local'), isTrue);
    expect(assembly.within('/project/.local-other/app', '/project/.local'),
        isFalse);
    expect(assembly.within('/project/.local', '/project/.local'), isFalse);
  });
}
