// Asks the decision model for each bundled product's Aisle, samples the
// reference set a person labels, and prints the guide that person follows.
//
// Run from apps/mobile, after build_bundle.dart --aisle-input-only:
//
//   dart run tool/open_food_facts_bundle/label_aisles.dart label \
//     --ollama <base URL, for example http://localhost:11434> \
//     [--model clef] [--dev-only]
//
//   dart run tool/open_food_facts_bundle/label_aisles.dart sample --seed <integer>
//
//   dart run tool/open_food_facts_bundle/label_aisles.dart guide
//
// Exit status: 0 done, 1 incomplete or refused, 64 usage, 65 a data file that
// does not parse, 66 a missing aisle input, 69 the model or the endpoint
// unavailable.
//
// This never runs in CI and the app does not depend on it. The logic is in
// aisle_pipeline.dart. See docs/designs/food-aisles.md, "The labeller".

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:perennia/domain/nutrition/food_aisle.dart';

import 'aisle_pipeline.dart';

const _checkpointPath = 'build/open_food_facts_aisle_labels.checkpoint.ndjson';
const _usage = '''
Usage:
  dart run tool/open_food_facts_bundle/label_aisles.dart label --ollama <base URL> [--model <name>] [--dev-only]
  dart run tool/open_food_facts_bundle/label_aisles.dart sample --seed <integer>
  dart run tool/open_food_facts_bundle/label_aisles.dart guide''';

const _defaultModel = 'clef';
const _requestTimeout = Duration(seconds: 300);
const _attemptsPerProduct = 3;
const _retryDelay = Duration(seconds: 5);
const _stopAfterUnlabelledInARow = 10;
const _checkpointEvery = 500;
const _progressEvery = 50;

const _exitDone = 0;
const _exitIncomplete = 1;
const _exitUsage = 64;
const _exitBadData = 65;
const _exitNoInput = 66;
const _exitUnavailable = 69;

Future<void> main(List<String> args) async {
  try {
    exitCode = await _run(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = _exitBadData;
  }
}

Future<int> _run(List<String> args) async {
  final options = args.skip(1).toList();
  switch (args.firstOrNull) {
    case 'guide' when options.isEmpty:
      stdout.write(aisleGuideText());
      return _exitDone;
    case 'sample':
      final values = _parseOptions(options, valued: {'--seed'});
      final seed = int.tryParse(values?['--seed'] ?? '');
      return seed == null ? _usageError() : _sample(seed);
    case 'label':
      final values = _parseOptions(
        options,
        valued: {'--ollama', '--model'},
        flags: {'--dev-only'},
      );
      final ollama = _ollamaBase(values?['--ollama']);
      final model = values?['--model'] ?? _defaultModel;
      if (values == null || ollama == null || model.isEmpty) {
        return _usageError();
      }
      return _label(
        ollama: ollama,
        modelOption: model,
        devOnly: values.containsKey('--dev-only'),
      );
    default:
      return _usageError();
  }
}

int _usageError() {
  stderr.writeln(_usage);
  return _exitUsage;
}

/// `--name value` or `--name=value` for [valued], a bare `--name` for [flags],
/// or `null` for anything else.
Map<String, String>? _parseOptions(
  List<String> args, {
  required Set<String> valued,
  Set<String> flags = const {},
}) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final [name, ...inline] = args[i].split('=');
    if (flags.contains(name) && inline.isEmpty) {
      values[name] = '';
      continue;
    }
    if (!valued.contains(name)) {
      return null;
    }
    final value = inline.isNotEmpty
        ? inline.join('=')
        : (i + 1 < args.length && !args[i + 1].startsWith('--')
            ? args[++i]
            : null);
    if (value == null) {
      return null;
    }
    values[name] = value;
  }
  return values;
}

/// The base URL with no trailing slash, or `null` when it cannot be one.
String? _ollamaBase(String? option) {
  final uri = option == null ? null : Uri.tryParse(option);
  if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
    return null;
  }
  return uri.host.isEmpty ? null : option!.replaceFirst(RegExp(r'/+$'), '');
}

// ---------------------------------------------------------------------------
// The data files.
// ---------------------------------------------------------------------------

/// A file that does not parse, or is not UTF-8, throws a [FormatException]
/// that names the path and keeps the parser's message. [main] exits 65 on it.
T _parseFile<T>(String path, T Function(String text) parse) {
  try {
    return parse(utf8.decode(File(path).readAsBytesSync()));
  } on FormatException catch (error) {
    throw FormatException('$path: ${error.message}');
  }
}

/// The aisle input, in code order, or `null` when there is none.
List<AisleInputLine>? _readAisleInput() {
  if (!File(aisleInputPath).existsSync()) {
    stderr.writeln(
      'No aisle input at $aisleInputPath: run build_bundle.dart '
      '--aisle-input-only first.',
    );
    return null;
  }
  return _parseFile(aisleInputPath, (text) {
    final lines = LineSplitter.split(text).toList();
    return [
      for (var i = 0; i < lines.length; i++)
        parseAisleInputLine(lines[i], lineNumber: i + 1),
    ]..sort((a, b) => a.code.compareTo(b.code));
  });
}

AisleLabels _readLabels(String path) {
  if (!File(path).existsSync()) {
    return const AisleLabels(header: null, byCode: {});
  }
  return _parseFile(path, parseAisleLabels);
}

List<AisleReferenceRow> _readReference() {
  if (!File(aisleReferencePath).existsSync()) {
    return const [];
  }
  return _parseFile(
    aisleReferencePath,
    (text) => parseAisleReference(text, allowUnlabelled: true),
  );
}

/// Through a temporary file next to [path] and a rename, so a run killed while
/// writing leaves the old file whole.
void _writeWhole(String path, String text) {
  final temporary = File('$path.tmp');
  temporary
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  temporary.renameSync(path);
}

// ---------------------------------------------------------------------------
// label.
// ---------------------------------------------------------------------------

Future<int> _label({
  required String ollama,
  required String modelOption,
  required bool devOnly,
}) async {
  final input = _readAisleInput();
  if (input == null) {
    return _exitNoInput;
  }
  final committed = _readLabels(aisleLabelsPath);
  final reference = _readReference();

  final client = HttpClient();
  try {
    final model = await _findModel(client, ollama, modelOption);
    if (model == null) {
      return _exitUnavailable;
    }
    final asker = _ModelAsker(client: client, ollama: ollama, model: model);
    return devOnly
        ? await _labelDevRows(asker, input, committed, reference)
        : await _labelEveryProduct(asker, input, committed, reference);
  } finally {
    client.close(force: true);
  }
}

Future<({String name, String digest})?> _findModel(
  HttpClient client,
  String ollama,
  String option,
) async {
  final url = '$ollama/api/tags';
  try {
    final response = await _exchange(client, Uri.parse(url));
    final match = response.status == 200
        ? matchOllamaModel(jsonDecode(response.body), option)
        : null;
    if (match == null) {
      stderr.writeln('$url does not list the model "$option".');
    }
    return match;
  } on Object catch (error) {
    if (!_isRequestFailure(error)) {
      rethrow;
    }
    stderr.writeln('Could not ask $url for the model "$option": $error');
    return null;
  }
}

/// The run that writes: every product with no reusable label is sent, and the
/// labels file is written once, at the end, under one question and one model.
Future<int> _labelEveryProduct(
  _ModelAsker asker,
  List<AisleInputLine> input,
  AisleLabels committed,
  List<AisleReferenceRow> reference,
) async {
  final header = AisleLabelsHeader(
    questionHash: aisleQuestionHash(),
    model: asker.model.name,
    modelDigest: asker.model.digest,
  );
  final checkpoint = _readCheckpoint(header);
  Map<String, AisleLabel> reusable(List<AisleLabels> sources) {
    return reusableLabels(
      input,
      sources,
      questionHash: header.questionHash,
      modelDigest: header.modelDigest,
    );
  }

  final reused = reusable([committed, checkpoint]);
  final fromEarlierRun = reusable([checkpoint]);
  final toSend = labelsToMake(input, reused);
  stderr
      .writeln('${toSend.length} products to label; ${reused.length} reused.');

  final made = await asker.ask(
    toSend,
    onCheckpoint: (made) => _writeWhole(
      _checkpointPath,
      encodeAisleLabels(
        AisleLabels(header: header, byCode: {...fromEarlierRun, ...made}),
      ),
    ),
  );
  if (made == null) {
    return _endpointMissing();
  }

  final labels = mergeLabels(
    input: input,
    reused: reused,
    made: made,
    header: header,
  );
  _writeWhole(aisleLabelsPath, encodeAisleLabels(labels));
  final checkpointFile = File(_checkpointPath);
  if (checkpointFile.existsSync()) {
    checkpointFile.deleteSync();
  }

  _printReport(
    reused: reused.length,
    made: made.length,
    unlabelled: toSend.length - made.length,
    counted: labels.byCode.values,
    input: input,
    labels: labels,
    reference: reference,
  );
  return made.length == toSend.length ? _exitDone : _exitIncomplete;
}

/// A checkpoint under another question or model gives no labels and is deleted.
AisleLabels _readCheckpoint(AisleLabelsHeader current) {
  final checkpoint = _readLabels(_checkpointPath);
  final header = checkpoint.header;
  if (header != null &&
      header.questionHash == current.questionHash &&
      header.modelDigest == current.modelDigest) {
    return checkpoint;
  }
  final file = File(_checkpointPath);
  if (file.existsSync()) {
    file.deleteSync();
  }
  return const AisleLabels(header: null, byCode: {});
}

/// The maintainer's quick try of a changed description. It writes nothing. Each
/// dev row's new label replaces its committed one, and every other product
/// keeps its committed label whatever its question hash, so Browse ranks are
/// those of the committed labels: enough to compare one change with the last
/// committed run. It leaves any checkpoint alone, even one under another
/// question, because a stopped full run may still need it.
Future<int> _labelDevRows(
  _ModelAsker asker,
  List<AisleInputLine> input,
  AisleLabels committed,
  List<AisleReferenceRow> reference,
) async {
  final devCodes = {
    for (final row in reference)
      if (row.set == ReferenceSet.dev) row.code,
  };
  final toSend = [
    for (final line in input)
      if (devCodes.contains(line.code)) line,
  ];
  stderr
      .writeln('${toSend.length} dev rows to label; nothing will be written.');

  final made = await asker.ask(toSend);
  if (made == null) {
    return _endpointMissing();
  }

  _printReport(
    reused: 0,
    made: made.length,
    unlabelled: toSend.length - made.length,
    counted: made.values,
    input: input,
    labels: AisleLabels(
      header: committed.header,
      byCode: {...committed.byCode, ...made},
    ),
    reference: reference,
  );
  return made.length == toSend.length ? _exitDone : _exitIncomplete;
}

int _endpointMissing() {
  stderr.writeln(
    'The server does not serve /v1/systemone; it needs a newer Ollama.',
  );
  return _exitUnavailable;
}

/// Sends products one at a time and applies the failure table in "The question
/// asked of the model".
final class _ModelAsker {
  _ModelAsker({
    required this.client,
    required String ollama,
    required this.model,
  }) : endpoint = Uri.parse('$ollama/v1/systemone');

  final HttpClient client;
  final Uri endpoint;
  final ({String name, String digest}) model;

  /// Only the very first request of a run can say the endpoint is missing. A
  /// 404 after that is one product's failure, retried like any other status.
  bool _sentARequest = false;

  /// The labels made, by code, or `null` when the first request returned 404.
  /// It stops early after [_stopAfterUnlabelledInARow] unlabelled in a row.
  Future<Map<String, AisleLabel>?> ask(
    List<AisleInputLine> lines, {
    void Function(Map<String, AisleLabel> made)? onCheckpoint,
  }) async {
    final made = <String, AisleLabel>{};
    final stopwatch = Stopwatch()..start();
    var unlabelledInARow = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final _Answer answer = await _labelOf(line);
      if (answer.endpointMissing) {
        return null;
      }
      final label = answer.label;
      if (label != null) {
        made[line.code] = label;
        unlabelledInARow = 0;
      } else {
        unlabelledInARow += 1;
        stderr.writeln('  ${line.code}: left unlabelled (${answer.failure})');
      }

      final done = i + 1;
      if (done % _checkpointEvery == 0) {
        onCheckpoint?.call(made);
      }
      if (done % _progressEvery == 0 || done == lines.length) {
        stderr.writeln(_progress(done, lines.length, stopwatch.elapsed));
      }
      if (unlabelledInARow >= _stopAfterUnlabelledInARow) {
        stderr.writeln(
          'Stopping: $_stopAfterUnlabelledInARow products in a row were left '
          'unlabelled.',
        );
        break;
      }
    }
    return made;
  }

  Future<_Answer> _labelOf(AisleInputLine line) async {
    final body = aisleModelRequest(
      model: model.name,
      state: aisleModelState(
        name: line.name,
        brand: line.brand,
        categories: line.categories,
      ),
    );
    Object? failure;
    for (var attempt = 0; attempt < _attemptsPerProduct; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_retryDelay);
      }
      final isFirstRequest = !_sentARequest;
      _sentARequest = true;
      try {
        final response = await _exchange(client, endpoint, jsonBody: body);
        if (response.status == 404 && isFirstRequest) {
          return const _Answer.endpointMissing();
        }
        if (response.status != 200) {
          failure = 'HTTP ${response.status}';
          continue;
        }
        final label = aisleLabelFromResponse(
          jsonDecode(response.body),
          inputHash: line.inputHash,
        );
        if (label != null) {
          return _Answer.labelled(label);
        }
        failure = 'no usable answer';
      } on Object catch (error) {
        if (!_isRequestFailure(error)) {
          rethrow;
        }
        // A FormatException's text repeats the whole body.
        failure = error is FormatException ? 'a body that is not JSON' : error;
      }
    }
    return _Answer.failed(failure);
  }
}

final class _Answer {
  const _Answer.labelled(AisleLabel this.label)
      : failure = null,
        endpointMissing = false;
  const _Answer.failed(this.failure)
      : label = null,
        endpointMissing = false;
  const _Answer.endpointMissing()
      : label = null,
        failure = null,
        endpointMissing = true;

  final AisleLabel? label;
  final Object? failure;
  final bool endpointMissing;
}

/// Connection refused, a timeout, a dropped connection, or a body that is not
/// UTF-8 or JSON.
bool _isRequestFailure(Object error) {
  return error is IOException ||
      error is TimeoutException ||
      error is FormatException;
}

/// One request and its whole response, within the timeout.
Future<({int status, String body})> _exchange(
  HttpClient client,
  Uri uri, {
  Object? jsonBody,
}) async {
  HttpClientRequest? request;
  Future<({int status, String body})> send() async {
    final opened =
        jsonBody == null ? await client.getUrl(uri) : await client.postUrl(uri);
    request = opened;
    if (jsonBody != null) {
      final bytes = utf8.encode(jsonEncode(jsonBody));
      opened.headers.contentType = ContentType.json;
      opened.contentLength = bytes.length;
      opened.add(bytes);
    }
    final response = await opened.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  }

  try {
    return await send().timeout(_requestTimeout);
  } on TimeoutException {
    request?.abort();
    rethrow;
  }
}

String _progress(int done, int total, Duration elapsed) {
  final secondsEach = elapsed.inMilliseconds / 1000 / done;
  final left = Duration(seconds: (secondsEach * (total - done)).round());
  return '  $done of $total done, ${secondsEach.toStringAsFixed(1)} s each, '
      'about ${_duration(left)} left';
}

String _duration(Duration value) {
  final minutes = value.inMinutes % 60;
  final seconds = value.inSeconds % 60;
  return value.inHours > 0
      ? '${value.inHours} h $minutes min'
      : (minutes > 0 ? '$minutes min $seconds s' : '$seconds s');
}

/// [counted] holds the labels the choice and confidence counts are over: the
/// file just written, or a `--dev-only` run's new labels.
void _printReport({
  required int reused,
  required int made,
  required int unlabelled,
  required Iterable<AisleLabel> counted,
  required List<AisleInputLine> input,
  required AisleLabels labels,
  required List<AisleReferenceRow> reference,
}) {
  final byChoice = <FoodAisle?, int>{};
  var below = 0;
  var middle = 0;
  var high = 0;
  for (final label in counted) {
    byChoice[label.aisle] = (byChoice[label.aisle] ?? 0) + 1;
    if (label.confidence < aisleConfidenceThreshold) {
      below += 1;
    } else if (label.confidence < 0.9) {
      middle += 1;
    } else {
      high += 1;
    }
  }
  final measures = measureAisleLabels(
    bundle: resolveAisleBundle(
      input: input,
      labels: labels.byCode,
      reference: reference,
    ),
    reference: reference,
    labels: labels,
  );
  final out = StringBuffer()
    ..writeln('Aisle labels report')
    ..writeln('  labels reused:         $reused')
    ..writeln('  labels made:           $made')
    ..writeln('  unlabelled products:   $unlabelled')
    ..writeln('  by choice:');
  for (final aisle in FoodAisle.values) {
    out.writeln('    ${aisle.name.padRight(21)} ${byChoice[aisle] ?? 0}');
  }
  out
    ..writeln('    ${'other'.padRight(21)} ${byChoice[null] ?? 0}')
    ..writeln('  by confidence:')
    ..writeln('    ${'below 0.6'.padRight(21)} $below')
    ..writeln('    ${'0.6 to 0.9'.padRight(21)} $middle')
    ..writeln('    ${'0.9 and above'.padRight(21)} $high')
    ..writeln('  dev set measures:')
    ..writeAll(
      aisleSetMeasuresLines(measures.dev).map((line) => '    $line\n'),
    );
  stdout.write(out);
}

// ---------------------------------------------------------------------------
// sample.
// ---------------------------------------------------------------------------

/// Tops the reference set up to its counts, and refuses while any label is
/// missing or stale, because predictions from stale labels would skew the draw.
int _sample(int seed) {
  final input = _readAisleInput();
  if (input == null) {
    return _exitNoInput;
  }
  final labels = _readLabels(aisleLabelsPath);
  final existing = _readReference();

  final needLabels = input
      .where(
        (line) => !isCurrentLabel(
          labels.byCode[line.code],
          labels.header,
          line.inputHash,
        ),
      )
      .length;
  if (needLabels > 0) {
    stdout.writeln(
      '$needLabels products need labels: run label_aisles.dart label, '
      'then sample again.',
    );
    return _exitIncomplete;
  }

  final drawn = sampleReference(
    input: input,
    labels: labels.byCode,
    existing: existing,
    seed: seed,
  );
  _writeWhole(
      aisleReferencePath, encodeAisleReference([...existing, ...drawn]));
  stdout.writeln(
    'Drew ${drawn.length} rows; $aisleReferencePath now has '
    '${existing.length + drawn.length}.',
  );
  return _exitDone;
}
