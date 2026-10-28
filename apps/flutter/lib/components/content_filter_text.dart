import 'package:flutter/material.dart';

import '../logic/content_filter/app_content_filter.dart';
import '../logic/content_filter/content_filter_projection.dart';

/// A quoted passage can be revealed without allowing its author or siblings.
class ContentFilterText extends StatefulWidget {
  const ContentFilterText(
      {super.key, required this.source, required this.builder});
  final String source;
  final Widget Function(String source) builder;

  @override
  State<ContentFilterText> createState() => _ContentFilterTextState();
}

class _ContentFilterTextState extends State<ContentFilterText> {
  bool _revealed = false;

  @override
  void didUpdateWidget(ContentFilterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _revealed = false;
  }

  Widget _build(BuildContext context) {
    final clean = ContentFilterProjection.sanitizeQuotes(widget.source);
    if (_revealed || clean == widget.source) {
      return widget.builder(widget.source);
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.builder(clean),
          TextButton(
              onPressed: () => setState(() => _revealed = true),
              child: const Text('仅本次查看引用')),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final service = AppContentFilter.service;
    return service == null
        ? _build(context)
        : ListenableBuilder(
            listenable: service, builder: (context, _) => _build(context));
  }
}
