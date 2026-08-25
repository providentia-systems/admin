import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/platform/application_link_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Linux application-link channel forwards only bounded URI messages',
    () async {
      const channel = MethodChannel('providentia.admin.test.application_links');
      const codec = StandardMethodCodec();
      final source = LinuxApplicationLinkSource(channel: channel);
      final received = <Uri>[];
      final subscription = source.links.listen(received.add);
      await source.start();
      await source.start();

      Future<void> send(MethodCall call) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              codec.encodeMethodCall(call),
              (ByteData? _) {},
            );
      }

      const valid =
          'providentia-admin://login-link/admin#requestId='
          '11111111-1111-4111-8111-111111111111&approval='
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
      await send(const MethodCall('open', valid));
      await send(const MethodCall('ignored', valid));
      await send(const MethodCall('open', 42));
      await send(MethodCall('open', 'x' * 2049));

      expect(received, <Uri>[Uri.parse(valid)]);

      await subscription.cancel();
      await source.dispose();
    },
  );
}
