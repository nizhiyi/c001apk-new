import 'dart:io';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../network/captcha_retry_test.dart' show CaptchaAdapter;
import 'fakes.dart';

void main() {
  test('successful human verification must retain the imported identity',
      () async {
    final dir = await setupStorage();
    final mock = RegistrationOverride();
    HttpOverrides.global = mock;
    try {
      await GStorage.applySzlmId('DUsyntheticMANUALLYimported123');
      final request = Request();
      Request.dio.httpClientAdapter = CaptchaAdapter();
      request.captchaVerifier =
          (challenge) async => challenge.proof('synthetic-proof');
      final first =
          await request.get('https://api.coolapk.com/v6/feed/replyList');
      expect(first.extra['captchaVerification'], 'submitted');
      await request.get('https://api.coolapk.com/v6/feed/replyList');
      expect(mock.calls, 0,
          reason: 'A successful verifier must clear the queued rotation');
      expect(GStorage.szlmId, 'DUsyntheticMANUALLYimported123');
    } finally {
      HttpOverrides.global = null;
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
