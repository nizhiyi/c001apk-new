import 'dart:io';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../network/captcha_retry_test.dart' show CaptchaAdapter;
import 'fakes.dart';

void main() {
  test('a passive detail challenge never registers or rotates an identity',
      () async {
    final dir = await setupStorage();
    final mock = RegistrationOverride();
    HttpOverrides.global = mock;
    try {
      await GStorage.applySzlmId('DUsyntheticOLDexpired12345678');
      final request = Request();
      Request.dio.httpClientAdapter = CaptchaAdapter()..alwaysChallenge = true;
      request.captchaVerifier = (challenge) async => null;
      for (var i = 0; i < 2; i++) {
        await request.get('https://api.coolapk.com/v6/feed/detail',
            options: Options(extra: {'skipCaptcha': true}));
      }
      expect(mock.calls, 0,
          reason: 'Normal requests must retain the existing device identity');
      expect(GStorage.szlmId, 'DUsyntheticOLDexpired12345678');
    } finally {
      HttpOverrides.global = null;
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
