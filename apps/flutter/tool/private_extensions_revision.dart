import 'dart:convert';
import 'dart:io';

void main() {
  final lock =
      jsonDecode(File('../../private-extensions.lock.json').readAsStringSync())
          as Map;
  final revision = lock['revision'] as String;
  if (lock['repository'] != 'TG-Twilight/Flutter.Liquid.Glass' ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(revision)) {
    throw StateError('Invalid private extension lock');
  }
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null) {
    File(output)
        .writeAsStringSync('revision=$revision\n', mode: FileMode.append);
  }
  stdout.writeln('Official extension revision: $revision');
}
