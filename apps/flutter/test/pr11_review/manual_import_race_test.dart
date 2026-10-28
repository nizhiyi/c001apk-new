import 'dart:async';
import 'dart:io';
import 'package:c001apk_flutter/logic/szlm_identity_service.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'fakes.dart';

void main() {
  test(
      'a delayed automatic registration must not overwrite a newer manual import',
      () async {
    final dir = await setupStorage();
    final started = Completer<void>();
    final finish = Completer<String>();
    final mock = RegistrationOverride()
      ..result = () {
        started.complete();
        return finish.future;
      };
    HttpOverrides.global = mock;
    try {
      final pending = SzlmIdentityService.instance.renewNow();
      final checked = expectLater(pending, throwsException);
      await started.future;
      await GStorage.importOfficialDeviceIdentity(
          'ShuzlmID: DUsyntheticMANUALLYimported123');
      finish.complete('DUsyntheticAUTOMATIC123456789');
      await checked;
      expect(GStorage.szlmId, 'DUsyntheticMANUALLYimported123');
    } finally {
      HttpOverrides.global = null;
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
