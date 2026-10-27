import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/data/app_version.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_client.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

/// The only code that talks to Open Food Facts: what it sends, and how every
/// answer maps to an outcome (docs/designs/open-food-facts.md, "Live
/// requests").
void main() {
  final product = <String, Object?>{
    'code': '3017620422003',
    'product_name': 'Hazelnut cocoa spread',
    'brands': 'Nutella',
    'last_modified_t': 1760000000,
    'unique_scans_n': 12,
    'nutriments': <String, Object?>{'energy-kcal_100g': 539},
  };

  OpenFoodFactsClient clientFor(
    Future<http.Response> Function(http.Request request) handler, {
    DateTime Function()? clock,
  }) {
    return OpenFoodFactsClient(
      baseUrl: Uri.parse('https://off.test/'),
      httpClient: MockClient(handler),
      clock: clock,
    );
  }

  http.Response json(Object body, [int status = 200]) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }

  test('sends only the query, the fields, the User-Agent and accept', () async {
    final requests = <http.Request>[];
    final client = clientFor((request) async {
      requests.add(request);
      return request.url.path.endsWith('search.pl')
          ? json(<String, Object?>{
              'products': <Object?>[product]
            })
          : json(<String, Object?>{'status': 'success', 'product': product});
    });

    await client.search('nutella jar');
    await client.product('3017620422003');

    final search = requests.first;
    expect(search.method, 'GET');
    expect(search.url.host, 'off.test');
    expect(search.url.path, '/cgi/search.pl');
    expect(search.url.queryParameters, <String, String>{
      'search_terms': 'nutella jar',
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '20',
      'page': '1',
      'sort_by': 'unique_scans_n',
      'fields': openFoodFactsFields,
    });
    final lookup = requests.last;
    expect(lookup.url.path, '/api/v3.6/product/3017620422003.json');
    expect(lookup.url.queryParameters, <String, String>{
      'fields': openFoodFactsFields,
    });
    for (final request in requests) {
      expect(request.headers, <String, String>{
        'accept': 'application/json',
        'user-agent': 'Perennia/${perenniaAppVersion.split('+').first} '
            '($openFoodFactsContactEmail)',
      });
      expect(request.body, isEmpty);
    }
  });

  test('maps search results, leaving excluded products out', () async {
    final client = clientFor((request) async {
      return json(<String, Object?>{
        'products': <Object?>[
          product,
          <String, Object?>{'code': '1', 'last_modified_t': 1},
          'not a product',
        ],
      });
    });

    final outcome = await client.search('nutella');

    expect(outcome, isA<OpenFoodFactsResults>());
    final products = (outcome as OpenFoodFactsResults).products;
    expect(products.single.code, '3017620422003');
    expect(products.single.brand, 'Nutella');
  });

  test('reads a v3.6 found body, with the requested code as fallback',
      () async {
    final client = clientFor((request) async {
      return json(<String, Object?>{
        'status': 'success',
        'result': <String, Object?>{'id': 'product_found'},
        'product': <String, Object?>{...product}..remove('code'),
      });
    });

    final outcome = await client.product('3017620422003');

    expect(
      (outcome as OpenFoodFactsResults).products.single.code,
      '3017620422003',
    );
  });

  test('reads a v3.6 not-found body', () async {
    for (final status in <int>[200, 404]) {
      final client = clientFor((request) async {
        return json(<String, Object?>{
          'status': 'failure',
          'result': <String, Object?>{'id': 'product_not_found'},
        }, status);
      });

      expect(
        await client.product('0000000000000'),
        isA<OpenFoodFactsNotFound>(),
        reason: 'HTTP $status',
      );
    }
  });

  test('an excluded product reads as not found', () async {
    final client = clientFor((request) async {
      return json(<String, Object?>{
        'status': 'success',
        'product': <String, Object?>{'code': '1', 'product_name': 'No date'},
      });
    });

    expect(await client.product('1'), isA<OpenFoodFactsNotFound>());
  });

  test('maps each failure to its outcome and reason', () async {
    Future<OpenFoodFactsOutcome> outcomeFor(
      Future<http.Response> Function() respond,
    ) {
      return clientFor((_) => respond()).product('3017620422003');
    }

    expect(
      await outcomeFor(() async => http.Response('', 404)),
      isA<OpenFoodFactsNotFound>(),
    );
    for (final (status, reason) in <(int, OpenFoodFactsUnavailableReason)>[
      (429, OpenFoodFactsUnavailableReason.rateLimited),
      (503, OpenFoodFactsUnavailableReason.busy),
      (500, OpenFoodFactsUnavailableReason.httpError),
      (403, OpenFoodFactsUnavailableReason.httpError),
    ]) {
      final outcome = await outcomeFor(() async => http.Response('', status));
      expect(
        (outcome as OpenFoodFactsUnavailable).reason,
        reason,
        reason: 'HTTP $status',
      );
    }
    for (final body in <String>['<html>', '[]', '{"status":"success"}']) {
      final outcome = await outcomeFor(() async => http.Response(body, 200));
      expect(
        (outcome as OpenFoodFactsUnavailable).reason,
        OpenFoodFactsUnavailableReason.malformed,
        reason: body,
      );
    }
    expect(
      await outcomeFor(() async => throw const SocketException('offline')),
      isA<OpenFoodFactsOffline>(),
    );
    expect(
      await outcomeFor(() async => throw http.ClientException('refused')),
      isA<OpenFoodFactsOffline>(),
    );
  });

  testWidgets('a request with no answer in 10 seconds is offline',
      (tester) async {
    // testWidgets runs on a fake clock, so the timeout elapses at once.
    final client = clientFor((_) => Completer<http.Response>().future);
    OpenFoodFactsOutcome? outcome;
    unawaited(client.product('3017620422003').then((value) => outcome = value));

    await tester.pump(const Duration(seconds: 9));
    expect(outcome, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(outcome, isA<OpenFoodFactsOffline>());
  });

  test('the 11th search and the 16th product request in 60 s are not sent',
      () async {
    var now = DateTime.utc(2026, 10, 27, 12);
    var sent = 0;
    final client = clientFor(
      (request) async {
        sent += 1;
        return request.url.path.endsWith('search.pl')
            ? json(<String, Object?>{'products': <Object?>[]})
            : json(<String, Object?>{'status': 'success', 'product': product});
      },
      clock: () => now,
    );

    for (var i = 0; i < 10; i += 1) {
      expect(await client.search('q$i'), isA<OpenFoodFactsResults>());
    }
    final eleventh = await client.search('q10');
    expect(
      (eleventh as OpenFoodFactsUnavailable).reason,
      OpenFoodFactsUnavailableReason.budgetExceeded,
    );
    expect(sent, 10);

    for (var i = 0; i < 15; i += 1) {
      expect(await client.product('$i'), isA<OpenFoodFactsResults>());
    }
    final sixteenth = await client.product('16');
    expect(
      (sixteenth as OpenFoodFactsUnavailable).reason,
      OpenFoodFactsUnavailableReason.budgetExceeded,
    );
    expect(sent, 25);

    now = now.add(const Duration(seconds: 60));
    expect(await client.search('later'), isA<OpenFoodFactsResults>());
    expect(sent, 26);
  });

  test('the contact email is set before release', () {
    expect(
      openFoodFactsContactEmail,
      matches(RegExp(r'^[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+$')),
      reason: 'Open Food Facts asks for a project contact address in the '
          'User-Agent; set openFoodFactsContactEmail in '
          'lib/data/open_food_facts/open_food_facts_client.dart.',
    );
  });
}
