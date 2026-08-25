import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/security/secure_id.dart';

void main() {
  test('accepts backend UUIDv7 identities and client UUIDv4 intents', () {
    expect(isUuid('0198f4e2-7abc-7def-8abc-0123456789ab'), isTrue);
    expect(isUuid('11111111-1111-4111-8111-111111111111'), isTrue);
    expect(isUuid(newUuidV4()), isTrue);
  });

  test('rejects unsupported versions, variants, and non-canonical text', () {
    expect(isUuid('0198f4e2-7abc-0def-8abc-0123456789ab'), isFalse);
    expect(isUuid('0198f4e2-7abc-7def-7abc-0123456789ab'), isFalse);
    expect(isUuid('{0198f4e2-7abc-7def-8abc-0123456789ab}'), isFalse);
    expect(isUuid('not-a-uuid'), isFalse);
  });
}
