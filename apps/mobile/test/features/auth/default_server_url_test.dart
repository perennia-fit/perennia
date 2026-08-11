import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';

void main() {
  test(
    'a stock build ships no default server, so it never contacts '
    'infrastructure the user did not choose',
    () {
      // The app is offline-first and account-free: an install that has never
      // been signed in has no server, and the sign-in screen shows an empty
      // field for the user to point at their own deployment.
      //
      // A distributor operating a hosted service injects its URL at build time
      // with `--dart-define=PERENNIA_DEFAULT_SERVER_URL=https://…`. Baking one
      // into the source instead would make every self-hosted and local-only
      // build reach for that operator's servers by default. If this test fails,
      // a default crept back into the source — inject it at build time instead.
      expect(defaultAuthServerUrl, isEmpty);
    },
  );
}
