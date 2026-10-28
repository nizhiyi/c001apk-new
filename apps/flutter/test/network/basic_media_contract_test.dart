import 'package:c001apk_flutter/constants/implementation_variant.dart';
import 'package:c001apk_flutter/logic/media/feed_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public media keeps ordinary image order and content owner', () {
    final items = FeedMedia.fromContent(
        urls: ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
        contentId: '12');
    expect(items.map((item) => item.sourceUrl),
        ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    expect(items.every((item) => item.contentId == '12'), isTrue);
  });
  test('public backend does not advertise native media from filename hints',
      () {
    final item =
        FeedMedia.fromUrl('https://image.coolapk.com/example_hdr_live.jpg');
    expect(item.isLivePhoto, isFalse);
    expect(item.isHdr, isFalse);
    expect(item.sdrHdUrls, isEmpty);
  }, skip: officialExtensions);
}
