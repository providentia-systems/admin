import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

/// Fetches operator media with the same session checks as every other read.
/// The backend decides whether the operator may inspect the requested image.
final class OperatorImage extends StatefulWidget {
  const OperatorImage({
    required this.api,
    required this.path,
    required this.label,
    required this.placeholder,
    super.key,
  });

  final AdminApi api;
  final String path;
  final String label;
  final IconData placeholder;

  @override
  State<OperatorImage> createState() => _OperatorImageState();
}

class _OperatorImageState extends State<OperatorImage> {
  Uint8List? _bytes;
  MemoryImage? _image;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(OperatorImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path || widget.api != oldWidget.api) {
      _clear();
      unawaited(_load());
    }
  }

  void _clear() {
    final image = _image;
    if (image != null) unawaited(image.evict());
    _bytes?.fillRange(0, _bytes!.length, 0);
    _bytes = null;
    _image = null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final response = await widget.api.get(widget.path);
      final bytes = response.bytes;
      final mediaType = response.headers['content-type']?.split(';').first;
      if (!mounted ||
          generation != _generation ||
          response.statusCode == 204 ||
          bytes.isEmpty ||
          bytes.length > 5 * 1024 * 1024 ||
          !const <String>{
            'image/png',
            'image/jpeg',
            'image/webp',
          }.contains(mediaType) ||
          !(response.headers['cache-control'] ?? '').toLowerCase().contains(
            'no-store',
          )) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      setState(() {
        _bytes = bytes;
        _image = MemoryImage(bytes);
      });
    } on Object {
      // A 401/403 is handled synchronously by AdminApi's authorization callback.
      // Missing media and failed reads retain the default without caching data.
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    image: true,
    child: SizedBox.square(
      dimension: 96,
      child: _image == null
          ? Icon(widget.placeholder, size: 56)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(
                image: _image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(widget.placeholder, size: 56),
              ),
            ),
    ),
  );
}
