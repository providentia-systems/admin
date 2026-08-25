import 'dart:async';

import 'package:flutter/services.dart';

abstract interface class ApplicationLinkSource {
  Stream<Uri> get links;
  Future<void> start();
  Future<void> dispose();
}

final class LinuxApplicationLinkSource implements ApplicationLinkSource {
  LinuxApplicationLinkSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('providentia.admin.application_links');

  final MethodChannel _channel;
  final StreamController<Uri> _links = StreamController<Uri>.broadcast(
    sync: true,
  );
  var _started = false;

  @override
  Stream<Uri> get links => _links.stream;

  @override
  Future<void> start() {
    if (_started) return Future<void>.value();
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open' || call.arguments is! String) return;
      final raw = call.arguments! as String;
      if (raw.isEmpty || raw.length > 2048) return;
      final uri = Uri.tryParse(raw);
      if (uri != null && !_links.isClosed) _links.add(uri);
    });
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _links.close();
  }
}
