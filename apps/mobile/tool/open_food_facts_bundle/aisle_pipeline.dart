// The logic of the Food Aisles pipeline: the question asked of the model, the
// three committed data files, reading the tags export, how a product's Aisle
// is decided, the second opinion's input and answers, and the edge cases a
// person reviews.
//
// It is pure (no dart:io), so the builder, the labeller and the CI test call
// the same code on the same inputs. See docs/designs/food-aisles.md.

import 'dart:convert';
import 'dart:math' show max;

import 'package:cryptography/dart.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';
import 'package:perennia/features/nutrition/import/csv_parser.dart';

/// Paths relative to apps/mobile. The three data files are committed; the
/// aisle input and the second opinion input are under the git-ignored build
/// directory.
const aisleInputPath = 'build/open_food_facts_aisle_input.ndjson';
const aisleLabelsPath = 'tool/open_food_facts_bundle/aisle_labels.ndjson';
const aisleSecondOpinionsPath =
    'tool/open_food_facts_bundle/aisle_second_opinions.ndjson';
const aisleOverridesPath = 'tool/open_food_facts_bundle/aisle_overrides.csv';
const aisleSecondOpinionInputPath =
    'build/open_food_facts_aisle_second_opinion_input.ndjson';

/// A label decides a product's Aisle when its confidence is at least this.
const aisleConfidenceThreshold = 0.6;

/// Name and brand are cut to this many Unicode code points (runes), so a cut
/// never splits a character.
const aisleModelTextLimit = 200;

/// The model sees this many of a product's most specific Open Food Facts tags.
const aisleModelTagLimit = 6;

/// The instructions of the model's question. Changing a word changes the
/// question hash, and so makes every committed label stale.
const aisleModelInstructions =
    'Which supermarket aisle does `product` belong in? The product name '
    'matters most; `brand` and any `open_food_facts_categories` are hints. '
    'Choose `other` only when no aisle fits.';

/// Each Aisle's description: the model's criterion and the labelling guide, so
/// the person and the model read the same definitions. Each is a complete,
/// positive definition that names only its own foods. Changing a word changes
/// the question hash, and so makes every committed label stale.
const aisleModelDescriptions = <FoodAisle, String>{
  FoodAisle.dairyEggs:
      'Milk, yoghurt, cheese, butter, cream, eggs and coffee creamers, and '
          'their plant-based alternatives: plant milks, yoghurts and cheeses, '
          'margarine and plant-based butters',
  FoodAisle.breadBakery:
      'Bread and bakery: loaves, rolls, buns, wraps, flatbreads, bagels, '
          'crumpets, English muffins, croissants, pains au chocolat, brioche and '
          'Danish pastries',
  FoodAisle.breakfastCereals:
      'Cereals eaten from a bowl: breakfast cereal, muesli, granola and '
          'granola clusters, oats and porridge',
  FoodAisle.meatSeafood:
      'Meat, poultry, fish and seafood in any form (fresh, frozen, canned, '
          'cured, deli or cooked), including sausages and bacon, and plant-based '
          'alternatives to them such as vegan burgers, vegan sausages and falafel',
  FoodAisle.fruitVeg:
      'Fruit and vegetables in any form (fresh, frozen, canned or dried), '
          'salad leaves, undressed salad mixes and fruit cups',
  FoodAisle.pantry:
      'Cooking staples and ingredients: pasta of any kind, including fresh '
          'filled pasta, rice, dried noodles, grains, pulses and canned beans, '
          'flour, sugar, baking ingredients, oils, vinegar, stock, tomato purée '
          'and paste, garlic and ginger pastes, herbs and spices',
  FoodAisle.saucesSpreads:
      'Sauces, gravy, condiments, dressings, mayonnaise, dips, sweet and '
          'savoury spreads, jams, honey, syrups such as maple and golden syrup, '
          'and nut butters',
  FoodAisle.snacks:
      'Savoury snacks and snack bars: chips, crisps, crackers, pretzels, '
          'popcorn, nuts, seeds, trail mix, rice cakes, granola bites, and cereal, '
          'muesli and granola bars',
  FoodAisle.sweetsDesserts:
      'Sweet treats: chocolate, lollies and candy, sherbet, biscuits and '
          'cookies, cakes, sweet muffins, ice cream, puddings and desserts',
  FoodAisle.drinks:
      'Non-alcoholic drinks and what they are made from: water, soft drinks, '
          'juice, cordial and concentrates, coffee, tea, drink powders such as hot '
          'chocolate, and energy and sports drinks',
  FoodAisle.alcohol:
      'Drinks containing alcohol: beer, wine, spirits, cider and premixed '
          'drinks',
  FoodAisle.readyMeals:
      'Food eaten as it is after at most heating or adding water: chilled, '
          'frozen and canned meals, soups, instant noodles, packet meals, '
          'heat-and-eat sides such as microwave rice, flavoured grain pouches and '
          'baked beans, pizza, pies, sandwiches, filled wraps, sushi, salads with '
          'dressing, grains, pasta or protein, and meal kits',
  FoodAisle.proteinSupplements:
      'Sports nutrition and dietary supplements: protein powders, protein bars '
          'and shakes, energy bars and gels, meal replacements, electrolyte '
          'tablets, vitamins, fish oil and other supplements',
  FoodAisle.babyFood: 'Infant formula and food made for babies and toddlers',
};

/// The order of principles that settles every boundary between Aisles. It is
/// applied when the descriptions are written, not by the model, and it is
/// printed in the labelling guide. It is not part of the question hash.
const aislePrinciples = <String>[
  'Who it is for. Babies and toddlers (Baby food), adults drinking alcohol '
      '(Alcohol), people buying sports nutrition or dietary supplements '
      '(Protein & supplements).',
  'How it is prepared. Food eaten as it is after at most heating or adding '
      'water (Ready meals).',
  'What it is made of. A basic food of one kind, fresh, frozen, canned or '
      'dried, rather than a snack, sweet or drink made from it: dairy or eggs '
      '(Dairy & eggs), meat or fish (Meat & seafood), fruit or vegetables '
      '(Fruit & vegetables), bread and bakery (Bread & bakery). A plant-based '
      'alternative sits with the food it replaces.',
  'What form it takes. A cereal eaten from a bowl (Breakfast cereals), a snack '
      '(Snacks), a sweet treat (Sweets & desserts), a drink (Drinks), a sauce '
      'or spread (Sauces & spreads).',
  'Otherwise a cooking staple or ingredient (Pantry).',
];

/// `review` shows at most this many edge cases a run.
const aisleReviewLimit = 50;

/// At least this share of bundled products must have an Aisle. CI checks it,
/// to catch a broken run, not a poor label: it sits just below the 88% the
/// definitions experiment kept on confidence alone.
const aisleCoverageFloor = 0.85;

const _labelsFormat = 'perennia-open-food-facts-aisle-labels';
const _labelsFormatVersion = 1;
const _secondOpinionsFormat = 'perennia-open-food-facts-aisle-second-opinions';
const _secondOpinionsFormatVersion = 1;
const _secondOpinionAnswerInstruction =
    'Reply with exactly one id from criteria, for each product.';
const _otherChoice = 'other';
const _noneAnswer = 'none';
const _unsureAnswer = 'unsure';
const _tagPrefix = 'en:';
const _nullTag = 'en:null';
const _overrideColumns = <String>[
  'code',
  'name',
  'brand',
  'categories',
  'aisle'
];
const _tagsCodeColumn = 'code';
const _tagsCategoriesColumn = 'categories_tags';
const _tagsCountriesColumn = 'countries_tags';
const _stateKeys = <String>[
  'product',
  'brand',
  'open_food_facts_categories',
];

// ---------------------------------------------------------------------------
// The question asked of the model.
// ---------------------------------------------------------------------------

/// The `state` the model reads for one product. Its key order and the compact
/// JSON of it define [aisleInputHash], so a label goes stale exactly when what
/// the model would read changes.
Map<String, Object?> aisleModelState({
  required String name,
  String? brand,
  required List<String> categories,
}) {
  final tags = categories.where((tag) => tag.startsWith(_tagPrefix)).toList();
  final mostSpecific = tags.sublist(max(0, tags.length - aisleModelTagLimit));
  return <String, Object?>{
    _stateKeys[0]: _cutToRuneLimit(name),
    _stateKeys[1]: _cutToRuneLimit(brand ?? ''),
    _stateKeys[2]: [
      for (final tag in mostSpecific) tag.substring(_tagPrefix.length),
    ],
  };
}

String _cutToRuneLimit(String text) {
  if (text.length <= aisleModelTextLimit) {
    return text;
  }
  return String.fromCharCodes(text.runes.take(aisleModelTextLimit));
}

/// The body of one `POST /v1/systemone` request.
Map<String, Object?> aisleModelRequest({
  required String model,
  required Map<String, Object?> state,
}) {
  return <String, Object?>{
    'model': model,
    'state': state,
    'questions': <String, Object?>{
      'aisle': <String, Object?>{
        'type': 'choice',
        'instructions': aisleModelInstructions,
        'criteria': _criteria(aisleModelDescriptions),
      },
    },
  };
}

/// Every Aisle id in `FoodAisle` order, then `other` with `null`, which is how
/// the endpoint takes an option with no description.
Map<String, Object?> _criteria(Map<FoodAisle, String> descriptions) {
  return <String, Object?>{
    for (final aisle in FoodAisle.values) aisle.name: descriptions[aisle],
    _otherChoice: null,
  };
}

String aisleInputHash(Map<String, Object?> state) => _shortHash(state);

/// The hash of everything that defines the question: when it changes, every
/// label made under the old one is stale. No version number is bumped by hand.
String aisleQuestionHashOf({
  required String instructions,
  required Map<FoodAisle, String> descriptions,
}) {
  return _shortHash(<String, Object?>{
    'instructions': instructions,
    'criteria': _criteria(descriptions),
    'state': _stateKeys,
    'textLimit': aisleModelTextLimit,
    'tagLimit': aisleModelTagLimit,
  });
}

String aisleQuestionHash() {
  return aisleQuestionHashOf(
    instructions: aisleModelInstructions,
    descriptions: aisleModelDescriptions,
  );
}

/// The current question hash, worked out once: [isCurrentLabel] asks for it
/// for every product.
final String _currentQuestionHash = aisleQuestionHash();

/// The first 16 lowercase hexadecimal digits of the SHA-256 of the UTF-8 bytes
/// of the compact JSON. `jsonEncode` writes no spaces, keeps the map's key
/// order and writes characters outside ASCII as themselves.
String _shortHash(Object? value) {
  final hash = const DartSha256().hashSync(utf8.encode(jsonEncode(value)));
  return hash.bytes
      .take(8)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// The label in one `POST /v1/systemone` response, or `null` when it holds no
/// usable answer: a `choice` that is an Aisle id or `other`, and a `confidence`
/// from 0 to 1. Everything else in the response is ignored. The confidence is
/// rounded here, as the file rounds it, so the threshold reads the same value
/// in the run that made a label and in every run after it.
AisleLabel? aisleLabelFromResponse(
  Object? response, {
  required String inputHash,
}) {
  final answers = response is Map ? response['answers'] : null;
  final answer = answers is Map ? answers['aisle'] : null;
  if (answer is! Map) {
    return null;
  }
  final choice = answer['choice'];
  final confidence = answer['confidence'];
  if (choice is! String ||
      confidence is! num ||
      confidence < 0 ||
      confidence > 1) {
    return null;
  }
  final aisle = foodAisleById(choice);
  if (aisle == null && choice != _otherChoice) {
    return null;
  }
  return (
    inputHash: inputHash,
    aisle: aisle,
    confidence: _roundConfidence(confidence.toDouble()),
  );
}

double _roundConfidence(double confidence) {
  return double.parse(confidence.toStringAsFixed(3));
}

/// The model `--model` names in a `GET /api/tags` response: one whose `name`
/// equals [option], or, when [option] has no `:` tag, equals it followed by
/// `:latest`. `null` when none does.
({String name, String digest})? matchOllamaModel(
  Object? tags,
  String option,
) {
  final models = tags is Map ? tags['models'] : null;
  if (models is! List) {
    return null;
  }
  final names = {option, if (!option.contains(':')) '$option:latest'};
  for (final model in models) {
    final name = model is Map ? model['name'] : null;
    final digest = model is Map ? model['digest'] : null;
    if (name is String && digest is String && names.contains(name)) {
      return (name: name, digest: digest);
    }
  }
  return null;
}

/// What `label_aisles guide` prints, and the review page shows: what a person
/// follows when answering an edge case, built from the same constants as the
/// model's criteria.
String aisleGuideText() {
  final buffer = StringBuffer()
    ..writeln('The order of principles. The first that applies wins:')
    ..writeln();
  for (var i = 0; i < aislePrinciples.length; i += 1) {
    buffer.writeln('${i + 1}. ${aislePrinciples[i]}');
  }
  buffer
    ..writeln()
    ..writeln('The Aisles:')
    ..writeln();
  for (final aisle in FoodAisle.values) {
    buffer.writeln(
      '${aisle.name} (${aisle.label}): ${aisleModelDescriptions[aisle]}',
    );
  }
  buffer
    ..writeln()
    ..writeln('The other answers:')
    ..writeln()
    ..writeln('$_noneAnswer: no Aisle fits.')
    ..writeln('$_unsureAnswer: you cannot tell what the product is.');
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// The aisle input.
// ---------------------------------------------------------------------------

final class AisleInputLine {
  const AisleInputLine({
    required this.code,
    required this.name,
    required this.brand,
    required this.categories,
    required this.scans,
    required this.inputHash,
  });

  final String code;
  final String name;
  final String? brand;

  /// All the product's Open Food Facts tags, `en:` kept.
  final List<String> categories;
  final int scans;
  final String inputHash;
}

/// Parses one line of the aisle input. [lineNumber] is the line's 1-based
/// number in its file, which a [FormatException] names.
AisleInputLine parseAisleInputLine(String line, {int lineNumber = 1}) {
  final json = _decodeObject(line, lineNumber);
  _requireExactKeys(
      json,
      const {
        'code',
        'name',
        'brand',
        'categories',
        'scans',
        'inputHash',
      },
      lineNumber);
  final brand = json['brand'];
  final categories = json['categories'];
  final scans = json['scans'];
  if (brand != null && brand is! String) {
    throw _formatError(lineNumber, '"brand" is not text or null');
  }
  if (categories is! List || categories.any((tag) => tag is! String)) {
    throw _formatError(lineNumber, '"categories" is not a list of text');
  }
  if (scans is! int) {
    throw _formatError(lineNumber, '"scans" is not an integer');
  }
  return AisleInputLine(
    code: _requireString(json, 'code', lineNumber),
    name: _requireString(json, 'name', lineNumber),
    brand: brand as String?,
    categories: categories.cast<String>(),
    scans: scans,
    inputHash: _requireString(json, 'inputHash', lineNumber),
  );
}

String encodeAisleInputLine(AisleInputLine line) {
  return jsonEncode(<String, Object?>{
    'code': line.code,
    'name': line.name,
    'brand': line.brand,
    'categories': line.categories,
    'scans': line.scans,
    'inputHash': line.inputHash,
  });
}

// ---------------------------------------------------------------------------
// The labels file.
// ---------------------------------------------------------------------------

final class AisleLabelsHeader {
  const AisleLabelsHeader({
    required this.questionHash,
    required this.model,
    required this.modelDigest,
  });

  final String questionHash;
  final String model;
  final String modelDigest;
}

/// One product's label. `aisle` holds the file's `choice`; `null` means the
/// model chose `other`.
typedef AisleLabel = ({String inputHash, FoodAisle? aisle, double confidence});

final class AisleLabels {
  const AisleLabels({required this.header, required this.byCode});

  /// `null` means no file: no header and no labels.
  final AisleLabelsHeader? header;
  final Map<String, AisleLabel> byCode;
}

AisleLabels parseAisleLabels(String text) {
  if (text.isEmpty) {
    return const AisleLabels(header: null, byCode: {});
  }
  final lines = _dataLines(text);
  final header = _parseLabelsHeader(lines.first);
  final byCode = <String, AisleLabel>{};
  for (var i = 1; i < lines.length; i += 1) {
    final lineNumber = i + 1;
    final json = _decodeObject(lines[i], lineNumber);
    _requireExactKeys(
        json,
        const {
          'code',
          'inputHash',
          'choice',
          'confidence',
        },
        lineNumber);
    final code = _requireString(json, 'code', lineNumber);
    final inputHash = _requireString(json, 'inputHash', lineNumber);
    final aisle = _requireChoice(json, lineNumber);
    final confidence = json['confidence'];
    if (confidence is! num || confidence < 0 || confidence > 1) {
      throw _formatError(
          lineNumber, '"confidence" is not a number from 0 to 1');
    }
    if (byCode.containsKey(code)) {
      throw _formatError(lineNumber, 'repeated code "$code"');
    }
    byCode[code] = (
      inputHash: inputHash,
      aisle: aisle,
      confidence: confidence.toDouble(),
    );
  }
  return AisleLabels(header: header, byCode: byCode);
}

AisleLabelsHeader _parseLabelsHeader(String line) {
  const lineNumber = 1;
  final json = _decodeObject(line, lineNumber);
  _requireFormat(
    json,
    format: _labelsFormat,
    formatVersion: _labelsFormatVersion,
  );
  return AisleLabelsHeader(
    questionHash: _requireString(json, 'questionHash', lineNumber),
    model: _requireString(json, 'model', lineNumber),
    modelDigest: _requireString(json, 'modelDigest', lineNumber),
  );
}

/// The file's text: a header line, then one line per product sorted by code,
/// compact JSON, confidence rounded to 3 places. No header means no file, so
/// it encodes to empty text, and labels with no header cannot be written.
String encodeAisleLabels(AisleLabels labels) {
  final header = labels.header;
  if (header == null) {
    if (labels.byCode.isNotEmpty) {
      throw ArgumentError.value(labels, 'labels', 'labels with no header');
    }
    return '';
  }
  final buffer = StringBuffer()
    ..write(
      jsonEncode(<String, Object?>{
        'format': _labelsFormat,
        'formatVersion': _labelsFormatVersion,
        'questionHash': header.questionHash,
        'model': header.model,
        'modelDigest': header.modelDigest,
      }),
    )
    ..write('\n');
  final codes = labels.byCode.keys.toList()..sort();
  for (final code in codes) {
    final label = labels.byCode[code]!;
    buffer
      ..write(
        jsonEncode(<String, Object?>{
          'code': code,
          'inputHash': label.inputHash,
          'choice': label.aisle?.name ?? _otherChoice,
          'confidence': _roundConfidence(label.confidence),
        }),
      )
      ..write('\n');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// The second opinions file.
// ---------------------------------------------------------------------------

final class AisleSecondOpinionsHeader {
  const AisleSecondOpinionsHeader({
    required this.questionHash,
    required this.model,
  });

  final String questionHash;

  /// The name given to `second-opinion-apply`. A hosted model has no digest,
  /// so this name is all that is recorded of its version.
  final String model;
}

/// One product's second opinion. `aisle` holds the file's `choice`; `null`
/// means the model chose `other`. There is no confidence.
typedef AisleSecondOpinion = ({String inputHash, FoodAisle? aisle});

final class AisleSecondOpinions {
  const AisleSecondOpinions({required this.header, required this.byCode});

  /// `null` means no file: no header and no second opinions.
  final AisleSecondOpinionsHeader? header;
  final Map<String, AisleSecondOpinion> byCode;
}

AisleSecondOpinions parseAisleSecondOpinions(String text) {
  if (text.isEmpty) {
    return const AisleSecondOpinions(header: null, byCode: {});
  }
  final lines = _dataLines(text);
  final header = _parseSecondOpinionsHeader(lines.first);
  final byCode = <String, AisleSecondOpinion>{};
  for (var i = 1; i < lines.length; i += 1) {
    final lineNumber = i + 1;
    final json = _decodeObject(lines[i], lineNumber);
    _requireExactKeys(json, const {'code', 'inputHash', 'choice'}, lineNumber);
    final code = _requireString(json, 'code', lineNumber);
    final inputHash = _requireString(json, 'inputHash', lineNumber);
    final aisle = _requireChoice(json, lineNumber);
    if (byCode.containsKey(code)) {
      throw _formatError(lineNumber, 'repeated code "$code"');
    }
    byCode[code] = (inputHash: inputHash, aisle: aisle);
  }
  return AisleSecondOpinions(header: header, byCode: byCode);
}

AisleSecondOpinionsHeader _parseSecondOpinionsHeader(String line) {
  const lineNumber = 1;
  final json = _decodeObject(line, lineNumber);
  _requireFormat(
    json,
    format: _secondOpinionsFormat,
    formatVersion: _secondOpinionsFormatVersion,
  );
  return AisleSecondOpinionsHeader(
    questionHash: _requireString(json, 'questionHash', lineNumber),
    model: _requireString(json, 'model', lineNumber),
  );
}

/// The file's text: a header line, then one line per product sorted by code,
/// compact JSON. No header means no file, so it encodes to empty text.
String encodeAisleSecondOpinions(AisleSecondOpinions opinions) {
  final header = opinions.header;
  if (header == null) {
    if (opinions.byCode.isNotEmpty) {
      throw ArgumentError.value(
        opinions,
        'opinions',
        'second opinions with no header',
      );
    }
    return '';
  }
  final buffer = StringBuffer()
    ..write(
      jsonEncode(<String, Object?>{
        'format': _secondOpinionsFormat,
        'formatVersion': _secondOpinionsFormatVersion,
        'questionHash': header.questionHash,
        'model': header.model,
      }),
    )
    ..write('\n');
  final codes = opinions.byCode.keys.toList()..sort();
  for (final code in codes) {
    final opinion = opinions.byCode[code]!;
    buffer
      ..write(
        jsonEncode(<String, Object?>{
          'code': code,
          'inputHash': opinion.inputHash,
          'choice': opinion.aisle?.name ?? _otherChoice,
        }),
      )
      ..write('\n');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// The overrides file.
// ---------------------------------------------------------------------------

/// A person's answer: an Aisle, `none` (no Aisle fits) or `unsure` (they
/// cannot tell what the product is).
enum AisleOverrideAnswer { aisle, none, unsure }

final class AisleOverrideRow {
  const AisleOverrideRow({
    required this.code,
    required this.name,
    required this.brand,
    required this.categories,
    required this.answer,
    required this.aisle,
  }) : assert((answer == AisleOverrideAnswer.aisle) == (aisle != null));

  final String code;

  /// [name], [brand] and [categories] are there so the diff can be read;
  /// nothing reads them.
  final String name;
  final String brand;

  /// The product's Open Food Facts tags when it was answered, `en:` kept.
  final List<String> categories;
  final AisleOverrideAnswer answer;

  /// Set only when [answer] is [AisleOverrideAnswer.aisle].
  final FoodAisle? aisle;
}

/// Parses the overrides file. It always has a header row, so empty text is
/// rejected: a missing file is the caller's no rows.
List<AisleOverrideRow> parseAisleOverrides(String csv) {
  final records = parseCsv(csv);
  if (records.isEmpty) {
    throw _formatError(1, 'there is no header row');
  }
  final header = records.first;
  if (header.join(',') != _overrideColumns.join(',')) {
    throw _formatError(
      1,
      'the columns are not ${_overrideColumns.join(',')}',
    );
  }

  final rows = <AisleOverrideRow>[];
  final codes = <String>{};
  // parseCsv gives records, and a quoted cell can hold line breaks, so the
  // line a record starts on is worked out from the breaks before it.
  var lineNumber = 1 + _lineCount(header);
  for (final record in records.skip(1)) {
    final row = _parseOverrideRecord(record, lineNumber: lineNumber);
    if (!codes.add(row.code)) {
      throw _formatError(lineNumber, 'repeated code "${row.code}"');
    }
    rows.add(row);
    lineNumber += _lineCount(record);
  }
  return rows;
}

int _lineCount(List<String> record) {
  return 1 + record.fold(0, (sum, cell) => sum + '\n'.allMatches(cell).length);
}

AisleOverrideRow _parseOverrideRecord(
  List<String> cells, {
  required int lineNumber,
}) {
  if (cells.length != _overrideColumns.length) {
    throw _formatError(
      lineNumber,
      'expected ${_overrideColumns.length} cells, found ${cells.length}',
    );
  }
  final aisleCell = cells[4];
  final aisle = foodAisleById(aisleCell);
  final AisleOverrideAnswer answer;
  if (aisle != null) {
    answer = AisleOverrideAnswer.aisle;
  } else if (aisleCell == _noneAnswer) {
    answer = AisleOverrideAnswer.none;
  } else if (aisleCell == _unsureAnswer) {
    answer = AisleOverrideAnswer.unsure;
  } else if (aisleCell.isEmpty) {
    throw _formatError(lineNumber, '"aisle" is empty');
  } else {
    throw _formatError(lineNumber, 'unknown aisle "$aisleCell"');
  }
  return AisleOverrideRow(
    code: cells[0],
    name: _removeFormulaPrefix(cells[1]),
    brand: _removeFormulaPrefix(cells[2]),
    categories: cells[3].isEmpty ? const [] : cells[3].split(' '),
    answer: answer,
    aisle: aisle,
  );
}

/// The overrides file's text. Data files are LF with a trailing newline,
/// unlike the CSV export's CRLF rows, so this writes its own rows with
/// [escapeCsvField].
String encodeAisleOverrides(List<AisleOverrideRow> rows) {
  final sorted = [...rows]..sort((a, b) => a.code.compareTo(b.code));
  final buffer = StringBuffer()
    ..write(_overrideColumns.join(','))
    ..write('\n');
  for (final row in sorted) {
    final cells = <String>[
      row.code,
      _addFormulaPrefix(row.name),
      _addFormulaPrefix(row.brand),
      row.categories.join(' '),
      _overrideAnswerText(row),
    ];
    buffer
      ..write(cells.map(escapeCsvField).join(','))
      ..write('\n');
  }
  return buffer.toString();
}

String _overrideAnswerText(AisleOverrideRow row) {
  return switch (row.answer) {
    AisleOverrideAnswer.aisle => row.aisle!.name,
    AisleOverrideAnswer.none => _noneAnswer,
    AisleOverrideAnswer.unsure => _unsureAnswer,
  };
}

const _formulaPrefix = "'";
const _formulaStarts = <String>{'=', '+', '-', '@', '\t', '\r'};

/// A spreadsheet runs a cell that starts with one of these as a formula, so a
/// person opening the file is protected by a leading `'`.
String _addFormulaPrefix(String cell) {
  if (cell.isNotEmpty && _formulaStarts.contains(cell[0])) {
    return '$_formulaPrefix$cell';
  }
  return cell;
}

String _removeFormulaPrefix(String cell) {
  if (cell.length > 1 &&
      cell[0] == _formulaPrefix &&
      _formulaStarts.contains(cell[1])) {
    return cell.substring(1);
  }
  return cell;
}

// ---------------------------------------------------------------------------
// The tags export.
// ---------------------------------------------------------------------------

/// Where the three columns the builder reads sit in the tags export's rows.
final class AisleTagsColumns {
  const AisleTagsColumns({
    required this.code,
    required this.categories,
    required this.countries,
  });

  final int code;
  final int categories;
  final int countries;
}

/// Finds the columns by name in the export's header row, which is tab
/// separated whatever the file's name says.
AisleTagsColumns parseAisleTagsHeader(String line) {
  final cells = line.split('\t');
  int column(String name) {
    final index = cells.indexOf(name);
    if (index < 0) {
      throw _formatError(1, 'the tags export has no "$name" column');
    }
    return index;
  }

  return AisleTagsColumns(
    code: column(_tagsCodeColumn),
    categories: column(_tagsCategoriesColumn),
    countries: column(_tagsCountriesColumn),
  );
}

/// One export row, or `null` when it has too few cells to hold the three
/// columns (the builder skips and counts it). Tags are the comma-separated
/// entries that start with `en:`, in order, prefix kept, leaving out
/// `en:null`, which the export writes for a product with none.
({String code, List<String> categories, List<String> countries})?
    parseAisleTagsRow(String line, AisleTagsColumns columns) {
  final cells = line.split('\t');
  final needed = max(columns.code, max(columns.categories, columns.countries));
  if (cells.length <= needed) {
    return null;
  }
  return (
    code: cells[columns.code],
    categories: _exportTags(cells[columns.categories]),
    countries: _exportTags(cells[columns.countries]),
  );
}

List<String> _exportTags(String cell) {
  return [
    for (final tag in cell.split(','))
      if (tag.startsWith(_tagPrefix) && tag != _nullTag) tag,
  ];
}

// ---------------------------------------------------------------------------
// Deciding a product's Aisle.
// ---------------------------------------------------------------------------

bool isCurrentLabel(
  AisleLabel? label,
  AisleLabelsHeader? header,
  String inputHash,
) {
  return label != null &&
      header != null &&
      header.questionHash == _currentQuestionHash &&
      label.inputHash == inputHash;
}

/// An Aisle id, at or above [aisleConfidenceThreshold]. `other` is never
/// confident, whatever its confidence.
bool isConfidentLabel(AisleLabel label) {
  return label.aisle != null && label.confidence >= aisleConfidenceThreshold;
}

/// The same rule as [isCurrentLabel]: the current question, and the product's
/// current input hash.
bool isCurrentSecondOpinion(
  AisleSecondOpinion? opinion,
  AisleSecondOpinionsHeader? header,
  String inputHash,
) {
  return opinion != null &&
      header != null &&
      header.questionHash == _currentQuestionHash &&
      opinion.inputHash == inputHash;
}

/// A bundled product's Aisle. The first step that gives an answer wins: the
/// person's override, then a confident current label, then a current second
/// opinion that names the same Aisle as the label, otherwise no Aisle. A
/// product whose two models both answered `other`, and every edge case nobody
/// gave an Aisle, has none.
FoodAisle? resolveFoodAisle({
  required AisleLabel? currentLabel,
  AisleSecondOpinion? currentSecondOpinion,
  AisleOverrideRow? override,
}) {
  switch (override?.answer) {
    case AisleOverrideAnswer.aisle:
      return override!.aisle;
    case AisleOverrideAnswer.none:
      return null;
    case AisleOverrideAnswer.unsure:
    case null:
      break;
  }
  if (currentLabel == null) {
    return null;
  }
  if (isConfidentLabel(currentLabel)) {
    return currentLabel.aisle;
  }
  final secondAisle = currentSecondOpinion?.aisle;
  if (secondAisle != null && secondAisle == currentLabel.aisle) {
    return secondAisle;
  }
  return null;
}

/// A bundled product, with its resolved Aisle.
typedef AisleBundleProduct = ({String code, int scans, FoodAisle? aisle});

/// [resolveFoodAisle] for each input line, in input order. [labels] and
/// [secondOpinions] hold what the caller treats as current; a code with no
/// label has only the override step.
List<AisleBundleProduct> resolveAisleBundle({
  required List<AisleInputLine> input,
  required Map<String, AisleLabel> labels,
  required Map<String, AisleSecondOpinion> secondOpinions,
  required List<AisleOverrideRow> overrides,
}) {
  final overrideByCode = {for (final row in overrides) row.code: row};
  return [
    for (final line in input)
      (
        code: line.code,
        scans: line.scans,
        aisle: resolveFoodAisle(
          currentLabel: labels[line.code],
          currentSecondOpinion: secondOpinions[line.code],
          override: overrideByCode[line.code],
        ),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Reusing and merging labels.
// ---------------------------------------------------------------------------

/// The labels that need no new request. A source counts only under the current
/// question and the running model's digest, and a label only when its input
/// hash is the product's current one. Later sources win, which is how a
/// checkpoint label beats a committed one.
Map<String, AisleLabel> reusableLabels(
  List<AisleInputLine> input,
  List<AisleLabels> sources, {
  required String questionHash,
  required String modelDigest,
}) {
  final reusable = <String, AisleLabel>{};
  for (final source in sources) {
    final header = source.header;
    if (header == null ||
        header.questionHash != questionHash ||
        header.modelDigest != modelDigest) {
      continue;
    }
    for (final line in input) {
      final label = source.byCode[line.code];
      if (label != null && label.inputHash == line.inputHash) {
        reusable[line.code] = label;
      }
    }
  }
  return reusable;
}

/// The input lines with no reusable label.
List<AisleInputLine> labelsToMake(
  List<AisleInputLine> input,
  Map<String, AisleLabel> reusable,
) {
  return [
    for (final line in input)
      if (!reusable.containsKey(line.code)) line,
  ];
}

/// The labels to write: only codes still in the input, a made label winning
/// over a reused one, all under one [header], so a file never holds labels
/// from two models or two questions.
AisleLabels mergeLabels({
  required List<AisleInputLine> input,
  required Map<String, AisleLabel> reused,
  required Map<String, AisleLabel> made,
  required AisleLabelsHeader header,
}) {
  final byCode = <String, AisleLabel>{};
  for (final line in input) {
    final label = made[line.code] ?? reused[line.code];
    if (label != null) {
      byCode[line.code] = label;
    }
  }
  return AisleLabels(header: header, byCode: byCode);
}

// ---------------------------------------------------------------------------
// The second opinion.
// ---------------------------------------------------------------------------

/// Whether [line] needs a second opinion at all: its current label is not
/// confident. A product with no current label cannot say yet.
bool _needsSecondOpinion(AisleInputLine line, AisleLabels labels) {
  final label = labels.byCode[line.code];
  return isCurrentLabel(label, labels.header, line.inputHash) &&
      !isConfidentLabel(label!);
}

/// The products to ask: a current label that is not confident (including
/// `other` at any confidence), and no current second opinion. In input order.
List<AisleInputLine> secondOpinionsToAsk(
  List<AisleInputLine> input,
  AisleLabels labels,
  AisleSecondOpinions opinions,
) {
  return [
    for (final line in input)
      if (_needsSecondOpinion(line, labels) &&
          !isCurrentSecondOpinion(
            opinions.byCode[line.code],
            opinions.header,
            line.inputHash,
          ))
        line,
  ];
}

/// The second opinion input: the question line, holding the same instructions
/// and criteria Clef is asked, then one line per product with the same state.
/// Clef's answer is in no line, so it cannot sway the second opinion.
String encodeSecondOpinionInput(List<AisleInputLine> lines) {
  final buffer = StringBuffer()
    ..write(
      jsonEncode(<String, Object?>{
        'instructions': aisleModelInstructions,
        'criteria': _criteria(aisleModelDescriptions),
        'answer': _secondOpinionAnswerInstruction,
      }),
    )
    ..write('\n');
  for (final line in lines) {
    buffer
      ..write(
        jsonEncode(<String, Object?>{
          'code': line.code,
          'state': aisleModelState(
            name: line.name,
            brand: line.brand,
            categories: line.categories,
          ),
        }),
      )
      ..write('\n');
  }
  return buffer.toString();
}

/// An answers file: JSON lines of exactly `code` and `choice`, in any order,
/// perhaps several files joined, so blank lines are skipped. Every code must be
/// one in [asked], once. Returns code to choice; `null` is `other`.
Map<String, FoodAisle?> parseSecondOpinionAnswers(
  String text, {
  required Set<String> asked,
}) {
  final answers = <String, FoodAisle?>{};
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    final lineNumber = i + 1;
    final line = lines[i];
    if (line.trim().isEmpty) {
      continue;
    }
    final json = _decodeObject(line, lineNumber);
    _requireExactKeys(json, const {'code', 'choice'}, lineNumber);
    final code = _requireString(json, 'code', lineNumber);
    final aisle = _requireChoice(json, lineNumber);
    if (!asked.contains(code)) {
      throw _formatError(
        lineNumber,
        'code "$code" is not in the second opinion input',
      );
    }
    if (answers.containsKey(code)) {
      throw _formatError(lineNumber, 'repeated code "$code"');
    }
    answers[code] = aisle;
  }
  return answers;
}

/// The second opinions to write, under [header]: for each product that still
/// needs one, its answer, or else its current line already in [existing] when
/// that file names the same model. Codes whose label is now confident, or not
/// current, or that left the input are dropped, so a file never holds answers
/// from two models or two questions.
AisleSecondOpinions mergeSecondOpinions({
  required List<AisleInputLine> input,
  required AisleLabels labels,
  required AisleSecondOpinions existing,
  required Map<String, FoodAisle?> answers,
  required AisleSecondOpinionsHeader header,
}) {
  final sameModel = existing.header?.model == header.model;
  final byCode = <String, AisleSecondOpinion>{};
  for (final line in input) {
    if (!_needsSecondOpinion(line, labels)) {
      continue;
    }
    if (answers.containsKey(line.code)) {
      byCode[line.code] =
          (inputHash: line.inputHash, aisle: answers[line.code]);
      continue;
    }
    final kept = existing.byCode[line.code];
    if (sameModel &&
        isCurrentSecondOpinion(kept, existing.header, line.inputHash)) {
      byCode[line.code] = kept!;
    }
  }
  return AisleSecondOpinions(header: header, byCode: byCode);
}

// ---------------------------------------------------------------------------
// Edge cases and the review page.
// ---------------------------------------------------------------------------

/// A product whose current label is not confident and whose current second
/// opinion is a different choice.
final class AisleEdgeCase {
  const AisleEdgeCase({
    required this.line,
    required this.label,
    required this.secondOpinion,
  });

  final AisleInputLine line;
  final AisleLabel label;
  final AisleSecondOpinion secondOpinion;
}

/// The edge cases with no row in [overrides] (an `unsure` row included),
/// most scanned first, then by code, at most [aisleReviewLimit]: a person's
/// time goes where most users look. Both models answering `other` is not an
/// edge case.
List<AisleEdgeCase> selectAisleEdgeCases({
  required List<AisleInputLine> input,
  required AisleLabels labels,
  required AisleSecondOpinions opinions,
  required List<AisleOverrideRow> overrides,
}) {
  final answered = {for (final row in overrides) row.code};
  final cases = <AisleEdgeCase>[];
  for (final line in input) {
    if (answered.contains(line.code) || !_needsSecondOpinion(line, labels)) {
      continue;
    }
    final opinion = opinions.byCode[line.code];
    if (!isCurrentSecondOpinion(opinion, opinions.header, line.inputHash)) {
      continue;
    }
    final label = labels.byCode[line.code]!;
    if (opinion!.aisle == label.aisle) {
      continue;
    }
    cases.add(AisleEdgeCase(line: line, label: label, secondOpinion: opinion));
  }
  cases.sort((a, b) {
    final byScans = b.line.scans.compareTo(a.line.scans);
    return byScans != 0 ? byScans : a.line.code.compareTo(b.line.code);
  });
  return cases.take(aisleReviewLimit).toList();
}

/// The review page: one self-contained HTML document, with nothing loaded from
/// elsewhere. It shows one product at a time and posts `{code, aisle}` as JSON
/// to [postPath]. Every product field is escaped as HTML text, because product
/// names are contributors' writing.
String aisleReviewPage(List<AisleEdgeCase> cases, {required String postPath}) {
  final buffer = StringBuffer()
    ..write('<!doctype html>\n')
    ..write('<html lang="en">\n<head>\n')
    ..write('<meta charset="utf-8">\n')
    ..write(
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n',
    )
    ..write('<title>Aisle review</title>\n')
    ..write('<style>$_reviewPageStyle</style>\n')
    ..write('</head>\n')
    ..write('<body data-post-path="${_escapeHtml(postPath)}">\n')
    ..write('<h1>Aisle review</h1>\n')
    ..write('<p id="remaining"></p>\n');
  for (final edgeCase in cases) {
    final line = edgeCase.line;
    final brand = line.brand;
    buffer
      ..write('<section class="case" data-code="${_escapeHtml(line.code)}" '
          'hidden>\n')
      ..write('<h2>${_escapeHtml(line.name)}</h2>\n')
      ..write('<dl>\n')
      ..write('<dt>Brand</dt><dd>'
          '${brand == null || brand.isEmpty ? '(none)' : _escapeHtml(brand)}'
          '</dd>\n')
      ..write('<dt>Code</dt><dd>${_escapeHtml(line.code)}</dd>\n')
      ..write('<dt>Scans</dt><dd>${line.scans}</dd>\n')
      ..write(
          '<dt>Clef</dt><dd>${_escapeHtml(_choiceText(edgeCase.label.aisle))}'
          ', confidence ${edgeCase.label.confidence.toStringAsFixed(3)}</dd>\n')
      ..write('<dt>Second opinion</dt><dd>'
          '${_escapeHtml(_choiceText(edgeCase.secondOpinion.aisle))}</dd>\n')
      ..write('<dt>Open Food Facts tags</dt><dd>');
    if (line.categories.isEmpty) {
      buffer.write('(none)');
    } else {
      buffer.write('<ul>');
      for (final tag in line.categories) {
        buffer.write('<li>${_escapeHtml(tag)}</li>');
      }
      buffer.write('</ul>');
    }
    buffer.write('</dd>\n</dl>\n</section>\n');
  }
  buffer.write('<div id="answers">\n');
  for (final aisle in FoodAisle.values) {
    buffer.write(
      '<button type="button" data-aisle="${aisle.name}">'
      '${_escapeHtml(aisle.label)}</button>\n',
    );
  }
  buffer
    ..write('<button type="button" data-aisle="$_noneAnswer">'
        'None: no Aisle fits</button>\n')
    ..write('<button type="button" data-aisle="$_unsureAnswer">'
        'Unsure: cannot tell what it is</button>\n')
    ..write('</div>\n')
    ..write('<p id="status" role="status"></p>\n')
    ..write('<details>\n<summary>The labelling guide</summary>\n')
    ..write('<pre>${_escapeHtml(aisleGuideText())}</pre>\n')
    ..write('</details>\n')
    ..write('<script>$_reviewPageScript</script>\n')
    ..write('</body>\n</html>\n');
  return buffer.toString();
}

String _choiceText(FoodAisle? aisle) {
  return aisle == null ? _otherChoice : '${aisle.label} (${aisle.name})';
}

String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

const _reviewPageStyle = '''
body { font-family: system-ui, sans-serif; max-width: 48rem; margin: 1rem auto; padding: 0 1rem; color: #1b1b1b; background: #fff; }
dt { font-weight: 600; margin-top: 0.5rem; }
dd { margin-left: 0; }
ul { margin: 0; padding-left: 1.25rem; }
#answers { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 1rem 0; }
#answers button { min-height: 48px; padding: 0 1rem; font-size: 1rem; }
pre { white-space: pre-wrap; }
''';

/// Shows the cases one at a time, and moves on only once the tool has written
/// the answer, so a page closed part way loses at most the answer in flight.
const _reviewPageScript = '''
(function () {
  var postPath = document.body.dataset.postPath;
  var cases = Array.prototype.slice.call(document.querySelectorAll('.case'));
  var answers = document.getElementById('answers');
  var remaining = document.getElementById('remaining');
  var status = document.getElementById('status');
  var index = 0;
  var busy = false;
  function show() {
    cases.forEach(function (section, i) { section.hidden = i !== index; });
    var left = cases.length - index;
    remaining.textContent = left > 0
      ? left + ' of ' + cases.length + ' remaining'
      : 'All ' + cases.length + ' answered. The tool has stopped; you can close this page.';
    answers.hidden = left === 0;
  }
  answers.addEventListener('click', function (event) {
    var button = event.target.closest('button[data-aisle]');
    if (!button || busy || index >= cases.length) { return; }
    busy = true;
    status.textContent = 'Saving...';
    fetch(postPath, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: cases[index].dataset.code, aisle: button.dataset.aisle })
    }).then(function (response) {
      if (!response.ok) { throw new Error('status ' + response.status); }
      index += 1;
      status.textContent = '';
      show();
    }).catch(function (error) {
      status.textContent = 'Not saved (' + error.message + '). Try again.';
    }).then(function () { busy = false; });
  });
  show();
})();
''';

// ---------------------------------------------------------------------------
// Parsing helpers. Every failure is a FormatException naming the 1-based line,
// counting a header line or header row.
// ---------------------------------------------------------------------------

FormatException _formatError(int lineNumber, String problem) {
  return FormatException('line $lineNumber: $problem');
}

/// The lines of a data file, which ends with a newline.
List<String> _dataLines(String text) {
  final lines = text.split('\n');
  if (lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

Map<String, Object?> _decodeObject(String line, int lineNumber) {
  final Object? json;
  try {
    json = jsonDecode(line);
  } on FormatException {
    throw _formatError(lineNumber, 'not valid JSON');
  }
  if (json is! Map<String, Object?>) {
    throw _formatError(lineNumber, 'not a JSON object');
  }
  return json;
}

void _requireExactKeys(
  Map<String, Object?> json,
  Set<String> keys,
  int lineNumber,
) {
  for (final key in keys) {
    if (!json.containsKey(key)) {
      throw _formatError(lineNumber, 'missing key "$key"');
    }
  }
  for (final key in json.keys) {
    if (!keys.contains(key)) {
      throw _formatError(lineNumber, 'unexpected key "$key"');
    }
  }
}

String _requireString(Map<String, Object?> json, String key, int lineNumber) {
  final value = json[key];
  if (value is! String) {
    throw _formatError(lineNumber, '"$key" is not text');
  }
  return value;
}

/// The `choice` key: an Aisle id, or `other` as `null`.
FoodAisle? _requireChoice(Map<String, Object?> json, int lineNumber) {
  final choice = _requireString(json, 'choice', lineNumber);
  final aisle = foodAisleById(choice);
  if (aisle == null && choice != _otherChoice) {
    throw _formatError(lineNumber, 'unknown choice "$choice"');
  }
  return aisle;
}

/// A data file's header line names its format and version.
void _requireFormat(
  Map<String, Object?> json, {
  required String format,
  required int formatVersion,
}) {
  const lineNumber = 1;
  if (json['format'] != format) {
    throw _formatError(lineNumber, 'the header\'s "format" is not $format');
  }
  if (json['formatVersion'] != formatVersion) {
    throw _formatError(
      lineNumber,
      'the header\'s "formatVersion" is not $formatVersion',
    );
  }
}
