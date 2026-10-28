import 'dart:math';

import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/nine_grid_view.dart';
import '../constants/constants.dart';
import '../utils/utils.dart';
import '../logic/media/feed_media.dart';

Map<String, dynamic> mediaGalleryArguments(List<String> urls,
    {List<FeedMedia>? mediaItems,
    String? contentId,
    MediaContentType contentType = MediaContentType.feed,
    int initialPage = 0}) {
  final provided = mediaItems ?? const <FeedMedia>[];
  final items = urls.isEmpty
      ? provided
      : urls.map((url) {
          final fallback = FeedMedia.fromUrl(url,
              contentId: contentId, contentType: contentType);
          for (final item in provided) {
            if (item.sourceUrl == url ||
                item.previewUrl == url ||
                item.originalUrl == fallback.originalUrl) {
              if (item.contentId?.trim().isNotEmpty == true ||
                  contentId == null) {
                return item;
              }
              return FeedMedia(
                sourceUrl: item.sourceUrl,
                previewUrl: item.previewUrl,
                videoUrl: item.videoUrl,
                isLivePhoto: item.isLivePhoto,
                isHdr: item.isHdr,
                contentId: contentId,
                contentType: contentType,
              );
            }
          }
          // Body-only images need an explicit owner; unrelated metadata must
          // never lend its content identity to a different URL.
          return fallback;
        }).toList();
  return {
    'imgList': items.map((item) => item.sourceUrl).toList(),
    'mediaItems': items,
    'initialPage': initialPage
  };
}

Widget mediaThumbnail(FeedMedia item,
    {double? width, double? height, BoxFit? fit}) {
  final isGif = item.sourceUrl.endsWith(Constants.SUFFIX_GIF);
  final isLong = !isGif && _isLongImage(item.sourceUrl);
  return Builder(
      builder: (context) => Stack(children: [
            networkImage(item.thumbnailUrl,
                width: width, height: height, fit: fit),
            if (isGif || isLong)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Wrap(alignment: WrapAlignment.end, children: [
                  if (isGif) _badge(context, 'GIF'),
                  if (isLong) _badge(context, '长图'),
                ]),
              ),
          ]));
}

Widget image(
  double maxWidth,
  List<String> picArr, {
  bool isFeedArticle = false,
  String? articleImg,
  List<FeedMedia>? mediaItems,
  String? contentId,
  MediaContentType contentType = MediaContentType.feed,
}) {
  if (isFeedArticle && articleImg != null && !picArr.contains(articleImg)) {
    picArr = [...picArr, articleImg];
  }
  final items = mediaGalleryArguments(picArr,
      mediaItems: mediaItems,
      contentId: contentId,
      contentType: contentType)['mediaItems'] as List<FeedMedia>;
  if (items.isEmpty) return const SizedBox.shrink();
  double imageWidth = (maxWidth - 2 * 5) / 3;
  double imageHeight = imageWidth;
  if (isFeedArticle || picArr.length == 1) {
    List<double> imageLp =
        Utils.getImageLp(isFeedArticle ? articleImg! : picArr[0]);
    double ratioWH = imageLp[0] / imageLp[1];
    double ratioHW = imageLp[1] / imageLp[0];
    double maxRatio = 22 / 9;
    imageWidth = isFeedArticle
        ? maxWidth
        : ratioWH > 1.5
            ? maxWidth
            : (ratioWH >= 1 || (imageLp[1] > imageLp[0] && ratioHW < 1.5))
                ? 2 * imageWidth
                : imageWidth;
    imageHeight = imageWidth * min(ratioHW, maxRatio);
  }
  return NineGridView(
    bigImageWidth: imageWidth,
    bigImageHeight: imageHeight,
    space: 5,
    height: isFeedArticle || picArr.length == 1 ? imageHeight : null,
    width: isFeedArticle || picArr.length == 1 ? imageWidth : maxWidth,
    itemCount: isFeedArticle ? 1 : picArr.length,
    itemBuilder: (context, index) => GestureDetector(
      onTap: () {
        final arguments = mediaGalleryArguments(picArr,
            mediaItems: items,
            contentId: contentId,
            contentType: contentType,
            initialPage: isFeedArticle ? picArr.indexOf(articleImg!) : index);
        Get.toNamed('/imageview', arguments: arguments);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: mediaThumbnail(
            items[isFeedArticle
                ? picArr.indexOf(articleImg!).clamp(0, items.length - 1)
                : index],
            width: imageWidth,
            height: imageHeight,
            fit: isFeedArticle || picArr.length == 1
                ? BoxFit.fill
                : BoxFit.cover,
          ),
        ),
      ),
    ),
  );
}

bool _isLongImage(String url) {
  List<double> imageLp = Utils.getImageLp(url);
  return imageLp[1] / imageLp[0] >= 22 / 9;
}

Widget _badge(BuildContext context, String title) {
  const fontSize = 12.0;
  return Container(
    margin: const EdgeInsets.all(5),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4)),
    child: Text(
      title,
      style: TextStyle(
        height: 1,
        fontSize: fontSize,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      strutStyle: StrutStyle(
        height: 1,
        leading: 0,
        fontSize: fontSize,
      ),
    ),
  );
}
