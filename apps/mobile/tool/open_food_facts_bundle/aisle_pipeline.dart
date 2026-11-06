// The logic of the Food Aisles pipeline: the question asked of the model, the
// committed data files, how a product's Aisle is decided, how the reference
// set is drawn and how the labels are measured against it.
//
// It is pure (no dart:io), so the builder, the labeller and the CI test call
// the same code on the same inputs. See docs/designs/food-aisles.md.

import 'dart:convert';
import 'dart:math' show Random, max, min;

import 'package:cryptography/dart.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';
import 'package:perennia/features/nutrition/import/csv_parser.dart';

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

const referenceTestRandomRows = 120;

/// Applies to an Aisle's Browse rows, and again to its rows outside Browse.
const referenceTestRowsPerAislePart = 15;
const referenceDevRandomRows = 100;
const referenceDevRowsPerAisle = 5;
const referenceDevNoAisleRows = 10;
const aisleMeasureMinimumRows = 15;
const aisleAgreementBar = 0.95;
const aisleCoverageBar = 0.85;
const aislePrecisionBar = 0.90;

const _labelsFormat = 'perennia-open-food-facts-aisle-labels';
const _labelsFormatVersion = 1;
const _otherChoice = 'other';
const _noneAnswer = 'none';
const _unsureAnswer = 'unsure';
const _tagPrefix = 'en:';
const _referenceColumns = <String>[
  'code',
  'name',
  'brand',
  'categories',
  'aisle',
  'sampled_as',
  'set',
];
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

/// What `label_aisles guide` prints: what a person follows when filling in the
/// reference set, built from the same constants as the model's criteria.
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
    final choice = _requireString(json, 'choice', lineNumber);
    final aisle = foodAisleById(choice);
    if (aisle == null && choice != _otherChoice) {
      throw _formatError(lineNumber, 'unknown choice "$choice"');
    }
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
  if (json['format'] != _labelsFormat) {
    throw _formatError(
        lineNumber, 'the header\'s "format" is not $_labelsFormat');
  }
  if (json['formatVersion'] != _labelsFormatVersion) {
    throw _formatError(
      lineNumber,
      'the header\'s "formatVersion" is not $_labelsFormatVersion',
    );
  }
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
          'confidence': double.parse(label.confidence.toStringAsFixed(3)),
        }),
      )
      ..write('\n');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// The reference set.
// ---------------------------------------------------------------------------

enum ReferenceAnswer { aisle, none, unsure, unlabelled }

enum ReferenceDraw { random, aisle, noAisle }

enum ReferenceSet { dev, test }

final class AisleReferenceRow {
  const AisleReferenceRow({
    required this.code,
    required this.name,
    required this.brand,
    required this.categories,
    required this.answer,
    required this.aisle,
    required this.sampledAs,
    required this.set,
  }) : assert((answer == ReferenceAnswer.aisle) == (aisle != null));

  final String code;
  final String name;
  final String brand;

  /// The product's Open Food Facts tags when the row was sampled, `en:` kept.
  final List<String> categories;
  final ReferenceAnswer answer;

  /// Set only when [answer] is [ReferenceAnswer.aisle].
  final FoodAisle? aisle;
  final ReferenceDraw sampledAs;
  final ReferenceSet set;
}

/// Parses the reference set. With `allowUnlabelled: false` (CI) an empty
/// `aisle` is rejected too. Unlike the labels file, the reference set always
/// has a header row, so empty text is rejected: a missing file is the caller's
/// no rows.
List<AisleReferenceRow> parseAisleReference(
  String csv, {
  required bool allowUnlabelled,
}) {
  final records = parseCsv(csv);
  if (records.isEmpty) {
    throw _formatError(1, 'there is no header row');
  }
  final header = records.first;
  if (header.join(',') != _referenceColumns.join(',')) {
    throw _formatError(
      1,
      'the columns are not ${_referenceColumns.join(',')}',
    );
  }

  final rows = <AisleReferenceRow>[];
  final codes = <String>{};
  // parseCsv gives records, and a quoted cell can hold line breaks, so the
  // line a record starts on is worked out from the breaks before it.
  var lineNumber = 1 + _lineCount(header);
  for (final record in records.skip(1)) {
    final row = _parseReferenceRecord(
      record,
      lineNumber: lineNumber,
      allowUnlabelled: allowUnlabelled,
    );
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

AisleReferenceRow _parseReferenceRecord(
  List<String> cells, {
  required int lineNumber,
  required bool allowUnlabelled,
}) {
  if (cells.length != _referenceColumns.length) {
    throw _formatError(
      lineNumber,
      'expected ${_referenceColumns.length} cells, found ${cells.length}',
    );
  }
  final aisleCell = cells[4];
  final aisle = foodAisleById(aisleCell);
  final ReferenceAnswer answer;
  if (aisle != null) {
    answer = ReferenceAnswer.aisle;
  } else if (aisleCell == _noneAnswer) {
    answer = ReferenceAnswer.none;
  } else if (aisleCell == _unsureAnswer) {
    answer = ReferenceAnswer.unsure;
  } else if (aisleCell.isEmpty) {
    if (!allowUnlabelled) {
      throw _formatError(lineNumber, '"aisle" is empty');
    }
    answer = ReferenceAnswer.unlabelled;
  } else {
    throw _formatError(lineNumber, 'unknown aisle "$aisleCell"');
  }
  final sampledAs = _enumByName(ReferenceDraw.values, cells[5]);
  if (sampledAs == null) {
    throw _formatError(lineNumber, 'unknown sampled_as "${cells[5]}"');
  }
  final set = _enumByName(ReferenceSet.values, cells[6]);
  if (set == null) {
    throw _formatError(lineNumber, 'unknown set "${cells[6]}"');
  }
  return AisleReferenceRow(
    code: cells[0],
    name: _removeFormulaPrefix(cells[1]),
    brand: _removeFormulaPrefix(cells[2]),
    categories: cells[3].isEmpty ? const [] : cells[3].split(' '),
    answer: answer,
    aisle: aisle,
    sampledAs: sampledAs,
    set: set,
  );
}

T? _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}

/// The reference set's text. Data files are LF with a trailing newline, unlike
/// the CSV export's CRLF rows, so this writes its own rows with
/// [escapeCsvField].
String encodeAisleReference(List<AisleReferenceRow> rows) {
  final sorted = [...rows]..sort((a, b) => a.code.compareTo(b.code));
  final buffer = StringBuffer()
    ..write(_referenceColumns.join(','))
    ..write('\n');
  for (final row in sorted) {
    final cells = <String>[
      row.code,
      _addFormulaPrefix(row.name),
      _addFormulaPrefix(row.brand),
      row.categories.join(' '),
      _encodeAnswer(row),
      row.sampledAs.name,
      row.set.name,
    ];
    buffer
      ..write(cells.map(escapeCsvField).join(','))
      ..write('\n');
  }
  return buffer.toString();
}

String _encodeAnswer(AisleReferenceRow row) {
  return switch (row.answer) {
    ReferenceAnswer.aisle => row.aisle!.name,
    ReferenceAnswer.none => _noneAnswer,
    ReferenceAnswer.unsure => _unsureAnswer,
    ReferenceAnswer.unlabelled => '',
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

/// A bundled product's Aisle. The first step that gives an answer wins: the
/// person's reference answer, then a current label at or above the threshold,
/// otherwise no Aisle. With no [reference] this is the product's **prediction**,
/// which sampling and measuring use so they judge the pipeline, not the
/// person's own answers.
FoodAisle? resolveFoodAisle({
  required AisleLabel? currentLabel,
  AisleReferenceRow? reference,
}) {
  switch (reference?.answer) {
    case ReferenceAnswer.aisle:
      return reference!.aisle;
    case ReferenceAnswer.none:
      return null;
    case ReferenceAnswer.unsure:
    case ReferenceAnswer.unlabelled:
    case null:
      break;
  }
  if (currentLabel != null &&
      currentLabel.confidence >= aisleConfidenceThreshold) {
    return currentLabel.aisle;
  }
  return null;
}

/// A bundled product, with its resolved Aisle.
typedef AisleBundleProduct = ({String code, int scans, FoodAisle? aisle});

/// [resolveFoodAisle] for each input line, in input order. [labels] holds the
/// labels the caller treats as current; a code with no label has only the
/// reference step.
List<AisleBundleProduct> resolveAisleBundle({
  required List<AisleInputLine> input,
  required Map<String, AisleLabel> labels,
  required List<AisleReferenceRow> reference,
}) {
  final referenceByCode = {for (final row in reference) row.code: row};
  return [
    for (final line in input)
      (
        code: line.code,
        scans: line.scans,
        aisle: resolveFoodAisle(
          currentLabel: labels[line.code],
          reference: referenceByCode[line.code],
        ),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Browse rows.
// ---------------------------------------------------------------------------

/// For each Aisle, its list: the products whose resolved Aisle it is, sorted
/// by `scans` descending, then `code` ascending, as the picker orders an Aisle.
final class AisleRanking {
  const AisleRanking._(this._lists);

  final Map<FoodAisle, List<AisleBundleProduct>> _lists;

  List<AisleBundleProduct> listOf(FoodAisle aisle) => _lists[aisle] ?? const [];
}

AisleRanking buildAisleRanking(List<AisleBundleProduct> bundle) {
  final lists = <FoodAisle, List<AisleBundleProduct>>{};
  for (final product in bundle) {
    final aisle = product.aisle;
    if (aisle != null) {
      (lists[aisle] ??= []).add(product);
    }
  }
  for (final list in lists.values) {
    list.sort((a, b) => _compareRank(a.scans, a.code, b.scans, b.code));
  }
  return AisleRanking._(lists);
}

int _compareRank(int scansA, String codeA, int scansB, String codeB) {
  final byScans = scansB.compareTo(scansA);
  return byScans != 0 ? byScans : codeA.compareTo(codeB);
}

/// A product's Browse rank in [aisle]: 1 plus the number of products in the
/// Aisle's list that come before it. It counts as in [aisle] whatever its
/// resolved Aisle, because sampling and measuring ask where it would sit if
/// [aisle] were right. Binary search, because this runs for every product: a
/// product already in the list does not precede itself, so the first position
/// not before it is the count either way.
int browseRank(
  AisleRanking ranking,
  FoodAisle aisle, {
  required String code,
  required int scans,
}) {
  final list = ranking.listOf(aisle);
  var low = 0;
  var high = list.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final other = list[middle];
    if (_compareRank(other.scans, other.code, scans, code) < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low + 1;
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
// Sampling the reference set.
// ---------------------------------------------------------------------------

/// Tops the reference set up to its counts and returns only the new rows, in
/// the order they were drawn. [labels] holds current labels only; `sample`
/// refuses to run otherwise.
///
/// Each cell's shortfall is counted from [existing] alone, never from rows
/// drawn earlier in this run: the first run draws the table's 720 rows, and a
/// later run tops up only what the file lacks. A row whose code has left the
/// input has no prediction and falls in no cell, so a top-up replaces it, and
/// it stays in the file because rows are never removed.
///
/// One [Random] serves the whole run and the draw order is fixed, with random
/// rows first so they stay a uniform sample of the input. The same inputs and
/// seed therefore give the same rows.
List<AisleReferenceRow> sampleReference({
  required List<AisleInputLine> input,
  required Map<String, AisleLabel> labels,
  required List<AisleReferenceRow> existing,
  required int seed,
}) {
  final ranking = buildAisleRanking(
    resolveAisleBundle(input: input, labels: labels, reference: existing),
  );
  final byCode = {for (final line in input) line.code: line};
  final sortedInput = [...input]..sort((a, b) => a.code.compareTo(b.code));
  final predictions = <String, FoodAisle?>{
    for (final line in input)
      line.code: resolveFoodAisle(currentLabel: labels[line.code]),
  };

  bool inBrowse(AisleInputLine line, FoodAisle aisle) {
    final rank = browseRank(
      ranking,
      aisle,
      code: line.code,
      scans: line.scans,
    );
    return rank <= aisleBrowseLimit;
  }

  final random = Random(seed);
  final taken = {for (final row in existing) row.code};
  final drawn = <AisleReferenceRow>[];

  void draw(
    ReferenceSet set,
    ReferenceDraw sampledAs,
    int count,
    bool Function(AisleInputLine line) eligible,
  ) {
    final alreadyInCell = existing.where((row) {
      final line = byCode[row.code];
      return row.set == set &&
          line != null &&
          eligible(line) &&
          (sampledAs != ReferenceDraw.random ||
              row.sampledAs == ReferenceDraw.random);
    }).length;
    final candidates = [
      for (final line in sortedInput)
        if (!taken.contains(line.code) && eligible(line)) line,
    ]..shuffle(random);
    for (final line in candidates.take(max(0, count - alreadyInCell))) {
      taken.add(line.code);
      drawn.add(
        AisleReferenceRow(
          code: line.code,
          name: line.name,
          brand: line.brand ?? '',
          categories: line.categories,
          answer: ReferenceAnswer.unlabelled,
          aisle: null,
          sampledAs: sampledAs,
          set: set,
        ),
      );
    }
  }

  bool anyProduct(AisleInputLine line) => true;
  draw(
    ReferenceSet.test,
    ReferenceDraw.random,
    referenceTestRandomRows,
    anyProduct,
  );
  draw(
    ReferenceSet.dev,
    ReferenceDraw.random,
    referenceDevRandomRows,
    anyProduct,
  );
  for (final aisle in FoodAisle.values) {
    draw(
      ReferenceSet.test,
      ReferenceDraw.aisle,
      referenceTestRowsPerAislePart,
      (line) => predictions[line.code] == aisle && inBrowse(line, aisle),
    );
    draw(
      ReferenceSet.test,
      ReferenceDraw.aisle,
      referenceTestRowsPerAislePart,
      (line) => predictions[line.code] == aisle && !inBrowse(line, aisle),
    );
    draw(
      ReferenceSet.dev,
      ReferenceDraw.aisle,
      referenceDevRowsPerAisle,
      (line) => predictions[line.code] == aisle,
    );
  }
  draw(
    ReferenceSet.dev,
    ReferenceDraw.noAisle,
    referenceDevNoAisleRows,
    (line) => predictions[line.code] == null,
  );
  return drawn;
}

// ---------------------------------------------------------------------------
// Measuring the labels.
// ---------------------------------------------------------------------------

/// `rows == 0` means not measured.
typedef AisleShare = ({int matched, int rows});

final class AisleSetMeasures {
  const AisleSetMeasures({
    required this.agreement,
    required this.coverage,
    required this.browsePrecision,
    required this.precision,
    required this.recall,
    required this.unsureRows,
    required this.unlabelledRows,
  });

  final AisleShare agreement;
  final AisleShare coverage;
  final Map<FoodAisle, AisleShare> browsePrecision;
  final Map<FoodAisle, AisleShare> precision;

  /// Reported only: 120 random rows give too few rows for most Aisles.
  final Map<FoodAisle, AisleShare> recall;

  /// Of the rows whose code is in the bundle.
  final int unsureRows;
  final int unlabelledRows;
}

final class AisleMeasures {
  const AisleMeasures({
    required this.dev,
    required this.test,
    required this.failures,
  });

  final AisleSetMeasures dev;
  final AisleSetMeasures test;

  /// The test set's failures only, in the spec's order and text forms.
  final List<String> failures;
}

/// Compares the pipeline with a person, using only committed data, so the
/// builder and the CI test get the same answer. Every label counts as current:
/// CI has no dump to recompute input hashes from, and the builder has already
/// refused stale labels.
AisleMeasures measureAisleLabels({
  required List<AisleBundleProduct> bundle,
  required List<AisleReferenceRow> reference,
  required AisleLabels labels,
}) {
  final ranking = buildAisleRanking(bundle);
  final required = <FoodAisle, _RequiredRows>{
    for (final aisle in FoodAisle.values)
      aisle: _RequiredRows.of(ranking.listOf(aisle).length),
  };
  AisleSetMeasures measure(ReferenceSet set) => _measureSet(
        set,
        bundle: bundle,
        reference: reference,
        labels: labels,
        ranking: ranking,
        required: required,
      );

  final test = measure(ReferenceSet.test);
  return AisleMeasures(
    dev: measure(ReferenceSet.dev),
    test: test,
    failures: _failures(test, required),
  );
}

/// How many rows each part of an Aisle needs: the minimum, or all of the
/// part's products when it has fewer.
final class _RequiredRows {
  const _RequiredRows(this.browse, this.outsideBrowse);

  factory _RequiredRows.of(int products) {
    final browse = min(products, aisleBrowseLimit);
    return _RequiredRows(
      min(browse, aisleMeasureMinimumRows),
      min(products - browse, aisleMeasureMinimumRows),
    );
  }

  final int browse;
  final int outsideBrowse;
}

final class _ShareCounter {
  int matched = 0;
  int rows = 0;

  void count({required bool matches}) {
    rows += 1;
    if (matches) {
      matched += 1;
    }
  }

  AisleShare get share => (matched: matched, rows: rows);
}

AisleSetMeasures _measureSet(
  ReferenceSet set, {
  required List<AisleBundleProduct> bundle,
  required List<AisleReferenceRow> reference,
  required AisleLabels labels,
  required AisleRanking ranking,
  required Map<FoodAisle, _RequiredRows> required,
}) {
  final scansByCode = {
    for (final product in bundle) product.code: product.scans
  };
  final agreement = _ShareCounter();
  final coverage = _ShareCounter();
  final browse = {for (final aisle in FoodAisle.values) aisle: _ShareCounter()};
  final outside = {
    for (final aisle in FoodAisle.values) aisle: _ShareCounter()
  };
  final recall = {for (final aisle in FoodAisle.values) aisle: _ShareCounter()};
  var unsureRows = 0;
  var unlabelledRows = 0;

  for (final row in reference) {
    final scans = scansByCode[row.code];
    if (row.set != set || scans == null) {
      continue;
    }
    if (row.answer == ReferenceAnswer.unsure) {
      unsureRows += 1;
      continue;
    }
    if (row.answer == ReferenceAnswer.unlabelled) {
      unlabelledRows += 1;
      continue;
    }

    final predicted = resolveFoodAisle(currentLabel: labels.byCode[row.code]);
    final person = row.aisle;
    if (row.sampledAs == ReferenceDraw.random) {
      if (predicted != null) {
        agreement.count(matches: predicted == person);
      }
      if (person != null) {
        coverage.count(matches: predicted != null);
        recall[person]!.count(matches: predicted == person);
      }
    }
    if (predicted != null) {
      final rank = browseRank(
        ranking,
        predicted,
        code: row.code,
        scans: scans,
      );
      final part = rank <= aisleBrowseLimit ? browse : outside;
      part[predicted]!.count(matches: predicted == person);
    }
  }

  return AisleSetMeasures(
    agreement: agreement.share,
    coverage: coverage.share,
    browsePrecision: {
      for (final aisle in FoodAisle.values)
        aisle: _partShare(browse[aisle]!, required[aisle]!.browse),
    },
    precision: {
      for (final aisle in FoodAisle.values)
        aisle: _partShare(outside[aisle]!, required[aisle]!.outsideBrowse),
    },
    recall: {
      for (final aisle in FoodAisle.values) aisle: recall[aisle]!.share,
    },
    unsureRows: unsureRows,
    unlabelledRows: unlabelledRows,
  );
}

/// A part the Aisle has no products in is not measured, even in the odd case
/// of a row predicted into it: a product predicted as the Aisle and resolved
/// elsewhere can rank just past a list of exactly 100.
AisleShare _partShare(_ShareCounter counter, int requiredRows) {
  return requiredRows == 0 ? (matched: 0, rows: 0) : counter.share;
}

List<String> _failures(
  AisleSetMeasures test,
  Map<FoodAisle, _RequiredRows> required,
) {
  final failures = <String>[];

  void overall(String name, AisleShare share, double bar) {
    if (share.rows == 0) {
      failures.add('overall $name: not measured');
    } else if (_isBelow(share, bar)) {
      failures.add(
        'overall $name ${_percentOf(share)} is below ${_percent(bar)} '
        '(n=${share.rows})',
      );
    }
  }

  overall('agreement', test.agreement, aisleAgreementBar);
  overall('coverage', test.coverage, aisleCoverageBar);

  for (final aisle in FoodAisle.values) {
    final id = aisle.name;
    final rows = required[aisle]!;

    final browse = test.browsePrecision[aisle]!;
    if (browse.rows < rows.browse) {
      failures.add(
        'too few rows for $id in Browse: ${browse.rows} of ${rows.browse}',
      );
    } else if (rows.browse > 0 && _isBelow(browse, aislePrecisionBar)) {
      failures.add(
        'browse precision for $id ${_percentOf(browse)} is below '
        '${_percent(aislePrecisionBar)} (n=${browse.rows})',
      );
    }

    final outside = test.precision[aisle]!;
    if (outside.rows < rows.outsideBrowse) {
      failures.add(
        'too few rows for $id outside Browse: '
        '${outside.rows} of ${rows.outsideBrowse}',
      );
    } else if (rows.outsideBrowse > 0 && _isBelow(outside, aislePrecisionBar)) {
      failures.add(
        'precision for $id outside Browse ${_percentOf(outside)} is below '
        '${_percent(aislePrecisionBar)} (n=${outside.rows})',
      );
    }
  }
  return failures;
}

/// Compared before rounding, so 189 of 199 fails a 95% bar although it prints
/// as 95.0%.
bool _isBelow(AisleShare share, double bar) => share.matched / share.rows < bar;

String _percentOf(AisleShare share) => _percent(share.matched / share.rows);

String _percent(double share) => '${(share * 100).toStringAsFixed(1)}%';

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
