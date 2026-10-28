import 'dart:io';
import 'package:c001apk_flutter/logic/szlm_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'fakes.dart';

void main() {
  test('failed registrations must observe the documented five minute cooldown',
      () async {
    final dir = await setupStorage();
    final mock = RegistrationOverride()
      ..result = () async => throw const SocketException('synthetic offline');
    HttpOverrides.global = mock;
    try {
      for (var i = 0; i < 5; i++) {
        SzlmIdentityService.instance.noteChallenge();
        await SzlmIdentityService.instance.beforeRequest();
      }
      expect(mock.calls, 0,
          reason: 'Passive challenges must never register a device');
    } finally {
      HttpOverrides.global = null;
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
