import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/nutrition/open_food_facts.dart';
import '../app_version.dart';

/// The project address Open Food Facts asks for in the User-Agent
/// (`AppName/Version (ContactEmail)`). It must be a project address, not a
/// personal one, and forks change it. A test fails while this is not an email
/// address, so the app cannot ship with the placeholder.
const openFoodFactsContactEmail = '<supplied by the maintainer>';

/// `Perennia/<version> (<contact email>)`, with the version before `+`.
String perenniaUserAgent() {
  return 'Perennia/${perenniaAppVersion.split('+').first} '
      '($openFoodFactsContactEmail)';
}

/// The only code that sends requests to Open Food Facts. A request is sent
/// only after a user action, carries only the search text or barcode, the
/// User-Agent and an `accept` header, and is never retried.
///
/// See docs/designs/open-food-facts.md, "Live requests".
class OpenFoodFactsClient {
  OpenFoodFactsClient({
    required http.Client httpClient,
    Uri? baseUrl,
    DateTime Function()? clock,
  })  : _httpClient = httpClient,
        _baseUrl = baseUrl ?? Uri.parse(openFoodFactsBaseUrl),
        _searchBudget = RequestBudget(capacity: 10, clock: clock),
        _productBudget = RequestBudget(capacity: 15, clock: clock);

  final http.Client _httpClient;
  final Uri _baseUrl;
  final RequestBudget _searchBudget;
  final RequestBudget _productBudget;

  static const timeout = Duration(seconds: 10);

  /// A full-text search through the legacy `search.pl`, the endpoint the Open
  /// Food Facts documentation lists for it.
  Future<OpenFoodFactsOutcome> search(String query) {
    final uri = _baseUrl.resolve('cgi/search.pl').replace(
      queryParameters: <String, String>{
        'search_terms': query,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '20',
        'page': '1',
        'sort_by': 'unique_scans_n',
        'fields': openFoodFactsFields,
      },
    );
    return _send(_searchBudget, uri, (body) {
      final products = body['products'];
      if (products is! List) {
        return null;
      }
      return OpenFoodFactsResults(_mapAll(products));
    });
  }

  /// One product by its code, through API v3.6.
  Future<OpenFoodFactsOutcome> product(String code) {
    final uri = _baseUrl
        .resolve('api/v3.6/product/${Uri.encodeComponent(code)}.json')
        .replace(
      queryParameters: const <String, String>{'fields': openFoodFactsFields},
    );
    return _send(_productBudget, uri, (body) {
      if (_isProductNotFound(body)) {
        return const OpenFoodFactsNotFound();
      }
      final product = body['product'];
      if (product is! Map) {
        return null;
      }
      final mapped = mapOpenFoodFactsProduct(
        Map<String, Object?>.from(product),
        fallbackCode: code,
      );
      return switch (mapped) {
        MappedOpenFoodFactsProduct() => OpenFoodFactsResults([mapped]),
        ExcludedOpenFoodFactsProduct() => const OpenFoodFactsNotFound(),
      };
    });
  }

  /// Sends one request if [budget] allows. [read] turns a decoded body into an
  /// outcome, or returns `null` when its shape is wrong (`malformed`).
  Future<OpenFoodFactsOutcome> _send(
    RequestBudget budget,
    Uri uri,
    OpenFoodFactsOutcome? Function(Map<String, Object?> body) read,
  ) async {
    if (!budget.tryAcquire()) {
      return const OpenFoodFactsUnavailable(
        OpenFoodFactsUnavailableReason.budgetExceeded,
      );
    }
    final http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'accept': 'application/json',
          'user-agent': perenniaUserAgent(),
        },
      ).timeout(timeout);
    } on TimeoutException {
      return const OpenFoodFactsOffline();
    } on SocketException {
      return const OpenFoodFactsOffline();
    } on http.ClientException {
      return const OpenFoodFactsOffline();
    }

    final status = response.statusCode;
    if (status == 404) {
      return const OpenFoodFactsNotFound();
    }
    if (status == 429) {
      return const OpenFoodFactsUnavailable(
        OpenFoodFactsUnavailableReason.rateLimited,
      );
    }
    if (status == 503) {
      return const OpenFoodFactsUnavailable(
          OpenFoodFactsUnavailableReason.busy);
    }
    if (!_isSuccess(status)) {
      return const OpenFoodFactsUnavailable(
        OpenFoodFactsUnavailableReason.httpError,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return const OpenFoodFactsUnavailable(
        OpenFoodFactsUnavailableReason.malformed,
      );
    }
    final outcome =
        decoded is Map ? read(Map<String, Object?>.from(decoded)) : null;
    return outcome ??
        const OpenFoodFactsUnavailable(
          OpenFoodFactsUnavailableReason.malformed,
        );
  }

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  static bool _isProductNotFound(Map<String, Object?> body) {
    final result = body['result'];
    return body['status'] == 'failure' &&
        result is Map &&
        result['id'] == 'product_not_found';
  }

  /// Maps every product in a search response; excluded ones are left out.
  static List<MappedOpenFoodFactsProduct> _mapAll(List<Object?> products) {
    return [
      for (final product in products)
        if (product is Map)
          if (mapOpenFoodFactsProduct(Map<String, Object?>.from(product))
              case final MappedOpenFoodFactsProduct mapped)
            mapped,
    ];
  }
}

sealed class OpenFoodFactsOutcome {
  const OpenFoodFactsOutcome();
}

class OpenFoodFactsResults extends OpenFoodFactsOutcome {
  const OpenFoodFactsResults(this.products);

  final List<MappedOpenFoodFactsProduct> products;
}

class OpenFoodFactsNotFound extends OpenFoodFactsOutcome {
  const OpenFoodFactsNotFound();
}

/// No connection, or no answer within [OpenFoodFactsClient.timeout].
class OpenFoodFactsOffline extends OpenFoodFactsOutcome {
  const OpenFoodFactsOffline();
}

/// Open Food Facts answered but cannot serve the request, or the local budget
/// stopped it. The user sees one "unavailable" line for every reason; the
/// reason is kept for tests.
class OpenFoodFactsUnavailable extends OpenFoodFactsOutcome {
  const OpenFoodFactsUnavailable(this.reason);

  final OpenFoodFactsUnavailableReason reason;
}

enum OpenFoodFactsUnavailableReason {
  /// HTTP 429.
  rateLimited,

  /// HTTP 503.
  busy,

  /// Any other non-2xx status.
  httpError,

  /// A body that does not parse, or has the wrong shape.
  malformed,

  /// The local request budget; nothing was sent.
  budgetExceeded,
}

/// A sliding 60-second window that allows at most [capacity] requests, kept
/// below Open Food Facts' published limits (10 searches and 15 product
/// requests a minute). It lives in memory, so restarting the app clears it.
class RequestBudget {
  RequestBudget({required this.capacity, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int capacity;
  final DateTime Function() _clock;
  final List<DateTime> _sent = [];

  static const window = Duration(seconds: 60);

  bool tryAcquire() {
    final now = _clock();
    _sent.removeWhere((at) => !now.isBefore(at.add(window)));
    if (_sent.length >= capacity) {
      return false;
    }
    _sent.add(now);
    return true;
  }
}
