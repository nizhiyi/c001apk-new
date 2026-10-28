import '../model/feed/datum.dart';
import 'feed_media.dart';
export 'feed_media.dart';

List<FeedMedia> mediaForDatum(Datum data,
        {MediaContentType type = MediaContentType.feed}) =>
    FeedMedia.fromContent(
        metadata: data.imageUriList,
        urls: data.picArr,
        contentId: data.id?.toString(),
        contentType: type);
