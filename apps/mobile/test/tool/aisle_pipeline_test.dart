import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';

import '../../tool/open_food_facts_bundle/aisle_pipeline.dart';

const _header = AisleLabelsHeader(
  questionHash: 'q1',
  model: 'clef:latest',
  modelDigest: 'd1',
);

const _headerLine =
    '{"format":"perennia-open-food-facts-aisle-labels","formatVersion":1,'
    '"questionHash":"q1","model":"clef:latest","modelDigest":"d1"}';

const _inputLine = '{"code":"0818290014313","name":"Greek Yogurt Plain Nonfat",'
    '"brand":"Chobani","categories":["en:dairies","en:yogurts"],"scans":412,'
    '"inputHash":"352594eedc0b9cad"}';

AisleLabel _label(FoodAisle? aisle,
    {double confidence = 0.9, String hash = 'h'}) {
  return (inputHash: hash, aisle: aisle, confidence: confidence);
}

AisleInputLine _line(String code, {int scans = 1, String hash = 'h'}) {
  return AisleInputLine(
    code: code,
    name: 'Product $code',
    brand: null,
    categories: const ['en:foods'],
    scans: scans,
    inputHash: hash,
  );
}

AisleReferenceRow _row(
  String code, {
  ReferenceAnswer answer = ReferenceAnswer.unlabelled,
  FoodAisle? aisle,
  ReferenceDraw sampledAs = ReferenceDraw.random,
  ReferenceSet set = ReferenceSet.test,
  String name = 'A name',
  String brand = 'A brand',
  List<String> categories = const ['en:foods'],
}) {
  return AisleReferenceRow(
    code: code,
    name: name,
    brand: brand,
    categories: categories,
    answer: aisle == null ? answer : ReferenceAnswer.aisle,
    aisle: aisle,
    sampledAs: sampledAs,
    set: set,
  );
}

String _code(int number) => number.toString().padLeft(6, '0');

Matcher _throwsFormatNamingLine(int line) {
  return throwsA(
    isA<FormatException>().having(
      (error) => error.message,
      'message',
      startsWith('line $line:'),
    ),
  );
}

/// Bundled products with their label and, when a person has answered, their
/// reference row. A product's resolved Aisle is its prediction here, so a
/// fixture's Browse rows are simply its most scanned products.
class _MeasureFixture {
  final bundle = <AisleBundleProduct>[];
  final labels = <String, AisleLabel>{};
  final reference = <AisleReferenceRow>[];
  int _next = 0;

  /// A product predicted as [predicted], with no reference row.
  String product(FoodAisle? predicted,
      {int scans = 1, double confidence = 0.9}) {
    final code = _code(_next);
    _next += 1;
    bundle.add((code: code, scans: scans, aisle: predicted));
    labels[code] = _label(predicted, confidence: confidence);
    return code;
  }

  void row(
    FoodAisle? predicted, {
    required FoodAisle? person,
    ReferenceDraw sampledAs = ReferenceDraw.aisle,
    ReferenceSet set = ReferenceSet.test,
    int scans = 1,
  }) {
    final code = product(predicted, scans: scans);
    reference.add(
      _row(
        code,
        aisle: person,
        answer: ReferenceAnswer.none,
        sampledAs: sampledAs,
        set: set,
      ),
    );
  }

  /// [matched] rows the person agrees with, then enough they do not, all
  /// outscoring anything added later so they stay in Browse.
  void browseRows(FoodAisle aisle, {required int matched, required int rows}) {
    for (var i = 0; i < rows; i += 1) {
      row(aisle, person: i < matched ? aisle : null, scans: 1000);
    }
  }

  /// Fills the Aisle's Browse rows with products outscoring anything added
  /// later, so later rows fall outside Browse.
  void fillBrowse(FoodAisle aisle) {
    for (var i = 0; i < aisleBrowseLimit; i += 1) {
      product(aisle, scans: 1000);
    }
  }

  AisleMeasures measure() {
    return measureAisleLabels(
      bundle: bundle,
      reference: reference,
      labels: AisleLabels(header: _header, byCode: labels),
    );
  }
}

void main() {
  group('FoodAisle', () {
    test('has the 14 values of the spec, in order', () {
      expect(FoodAisle.values.map((aisle) => aisle.name), [
        'dairyEggs',
        'breadBakery',
        'breakfastCereals',
        'meatSeafood',
        'fruitVeg',
        'pantry',
        'saucesSpreads',
        'snacks',
        'sweetsDesserts',
        'drinks',
        'alcohol',
        'readyMeals',
        'proteinSupplements',
        'babyFood',
      ]);
      expect(FoodAisle.fruitVeg.label, 'Fruit & vegetables');
    });

    test('foodAisleById finds an id and returns null for an unknown one', () {
      expect(foodAisleById('snacks'), FoodAisle.snacks);
      expect(foodAisleById('other'), isNull);
      expect(foodAisleById('Snacks'), isNull);
    });
  });

  group('aisleModelState', () {
    test('keeps en: tags, takes the last six and removes the prefix', () {
      final state = aisleModelState(
        name: 'A',
        brand: 'B',
        categories: const [
          'en:one',
          'en:two',
          'fr:skipped',
          'en:three',
          'en:four',
          'en:five',
          'de:skipped',
          'en:six',
          'en:seven',
          'en:eight',
        ],
      );

      expect(state['open_food_facts_categories'], [
        'three',
        'four',
        'five',
        'six',
        'seven',
        'eight',
      ]);
    });

    test('keeps the key order, with an empty list and empty brand', () {
      final state = aisleModelState(name: 'A', categories: const []);

      expect(
        jsonEncode(state),
        '{"product":"A","brand":"","open_food_facts_categories":[]}',
      );
    });

    test('leaves text at the limit alone and cuts text over it', () {
      expect(
        aisleModelState(
          name: 'n' * 200,
          brand: 'b' * 201,
          categories: const [],
        ),
        containsPair('product', 'n' * 200),
      );
      expect(
        aisleModelState(
          name: 'n' * 201,
          brand: 'b' * 201,
          categories: const [],
        )['brand'],
        'b' * 200,
      );
    });

    test('cuts on runes, keeping a non-BMP 200th rune whole', () {
      const emoji = '\u{1F34E}';
      expect(emoji.length, 2);
      final name = '${'n' * 199}${emoji}after';

      final cut = aisleModelState(name: name, categories: const [])['product']
          as String;

      expect(cut, '${'n' * 199}$emoji');
      expect(cut.runes.length, 200);
      expect(cut.length, 201);
    });

    test('counts runes, not code units, when text is all non-BMP', () {
      const emoji = '\u{1F34E}';

      final cut = aisleModelState(
        name: emoji * 150,
        categories: const [],
      )['product'];

      expect(cut, emoji * 150);
    });
  });

  group('aisleModelRequest', () {
    test('asks one choice question with every Aisle, then other as null', () {
      final state = aisleModelState(name: 'A', categories: const []);

      final request = aisleModelRequest(model: 'clef:latest', state: state);

      expect(request['model'], 'clef:latest');
      expect(request['state'], state);
      final questions = request['questions']! as Map<String, Object?>;
      final question = questions['aisle']! as Map<String, Object?>;
      expect(question['type'], 'choice');
      expect(question['instructions'], aisleModelInstructions);
      final criteria = question['criteria']! as Map<String, Object?>;
      expect(criteria.keys, [
        ...FoodAisle.values.map((aisle) => aisle.name),
        'other',
      ]);
      expect(criteria['other'], isNull);
      expect(criteria['babyFood'], aisleModelDescriptions[FoodAisle.babyFood]);
    });
  });

  group('aisleInputHash', () {
    test('hashes the Greek yoghurt state as the spec states', () {
      final state = aisleModelState(
        name: 'Greek Yogurt Plain Nonfat',
        brand: 'Chobani',
        categories: const [
          'en:dairies',
          'en:fermented-foods',
          'en:fermented-milk-products',
          'en:yogurts',
          'en:greek-style-yogurts',
        ],
      );

      expect(aisleInputHash(state), '352594eedc0b9cad');
    });

    test('hashes non-ASCII text as itself', () {
      final state =
          aisleModelState(name: 'Crème fraîche', categories: const []);

      expect(aisleInputHash(state), '4a9c0a1a6c166aae');
    });
  });

  group('aisleQuestionHashOf', () {
    String hash({
      String instructions = aisleModelInstructions,
      Map<FoodAisle, String> descriptions = aisleModelDescriptions,
    }) {
      return aisleQuestionHashOf(
        instructions: instructions,
        descriptions: descriptions,
      );
    }

    test('is 16 lowercase hexadecimal digits', () {
      expect(hash(), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('changes when one description changes', () {
      final changed = {...aisleModelDescriptions};
      changed[FoodAisle.snacks] = '${changed[FoodAisle.snacks]} and more';

      expect(hash(descriptions: changed), isNot(hash()));
    });

    test('changes when the instructions change', () {
      expect(hash(instructions: '$aisleModelInstructions.'), isNot(hash()));
    });

    test('hashes the object the spec lists, in that key order', () {
      final object = <String, Object?>{
        'instructions': 'I',
        'criteria': <String, Object?>{
          for (final aisle in FoodAisle.values) aisle.name: 'D',
          'other': null,
        },
        'state': ['product', 'brand', 'open_food_facts_categories'],
        'textLimit': 200,
        'tagLimit': 6,
      };

      expect(
        aisleQuestionHashOf(
          instructions: 'I',
          descriptions: {for (final aisle in FoodAisle.values) aisle: 'D'},
        ),
        aisleInputHash(object),
      );
    });

    test('aisleQuestionHash is the constants\' hash, on every call', () {
      expect(aisleQuestionHash(), hash());
      expect(aisleQuestionHash(), aisleQuestionHash());
    });
  });

  group('aisle input', () {
    test('a line round-trips', () {
      expect(encodeAisleInputLine(parseAisleInputLine(_inputLine)), _inputLine);
    });

    test('a null brand round-trips', () {
      const line =
          '{"code":"1","name":"N","brand":null,"categories":[],"scans":1,'
          '"inputHash":"h"}';

      expect(parseAisleInputLine(line).brand, isNull);
      expect(encodeAisleInputLine(parseAisleInputLine(line)), line);
    });

    test('a missing key throws, naming the line', () {
      final json = jsonDecode(_inputLine) as Map<String, Object?>
        ..remove('scans');

      expect(
        () => parseAisleInputLine(jsonEncode(json), lineNumber: 7),
        _throwsFormatNamingLine(7),
      );
    });

    test('an extra key throws, naming the line', () {
      final json = jsonDecode(_inputLine) as Map<String, Object?>;
      json['extra'] = 1;

      expect(
        () => parseAisleInputLine(jsonEncode(json), lineNumber: 8),
        _throwsFormatNamingLine(8),
      );
    });

    test('a wrong type throws, naming the line', () {
      for (final wrong in <String, Object?>{
        'code': 1,
        'name': null,
        'brand': 1,
        'categories': ['en:a', 1],
        'scans': '412',
        'inputHash': false,
      }.entries) {
        final json = jsonDecode(_inputLine) as Map<String, Object?>;
        json[wrong.key] = wrong.value;

        expect(
          () => parseAisleInputLine(jsonEncode(json), lineNumber: 9),
          _throwsFormatNamingLine(9),
          reason: wrong.key,
        );
      }
    });

    test('text that is not a JSON object throws, naming the line', () {
      expect(() => parseAisleInputLine('nope'), _throwsFormatNamingLine(1));
      expect(() => parseAisleInputLine('[]'), _throwsFormatNamingLine(1));
    });
  });

  group('labels file', () {
    const text = '$_headerLine\n'
        '{"code":"1","inputHash":"a","choice":"dairyEggs","confidence":0.943}\n'
        '{"code":"2","inputHash":"b","choice":"other","confidence":0.5}\n';

    test('a sorted, compact file round-trips', () {
      final labels = parseAisleLabels(text);

      expect(labels.header!.questionHash, 'q1');
      expect(labels.header!.model, 'clef:latest');
      expect(labels.header!.modelDigest, 'd1');
      expect(labels.byCode['1']!.aisle, FoodAisle.dairyEggs);
      expect(labels.byCode['2']!.aisle, isNull);
      expect(encodeAisleLabels(labels), text);
    });

    test('encoding sorts by code and rounds confidence to 3 places', () {
      final encoded = encodeAisleLabels(
        AisleLabels(
          header: _header,
          byCode: {
            '2': _label(null, confidence: 0.94349, hash: 'b'),
            '1': _label(FoodAisle.snacks, confidence: 0.9436, hash: 'a'),
          },
        ),
      );

      expect(
        encoded,
        '$_headerLine\n'
        '{"code":"1","inputHash":"a","choice":"snacks","confidence":0.944}\n'
        '{"code":"2","inputHash":"b","choice":"other","confidence":0.943}\n',
      );
    });

    test('an empty text is no file', () {
      final labels = parseAisleLabels('');

      expect(labels.header, isNull);
      expect(labels.byCode, isEmpty);
      expect(encodeAisleLabels(labels), '');
    });

    test('a header with no labels is a file', () {
      final labels = parseAisleLabels('$_headerLine\n');

      expect(labels.header, isNotNull);
      expect(labels.byCode, isEmpty);
    });

    test('labels with no header cannot be written', () {
      expect(
        () => encodeAisleLabels(
          AisleLabels(header: null, byCode: {'1': _label(null)}),
        ),
        throwsArgumentError,
      );
    });

    group('rejects', () {
      const good =
          '{"code":"1","inputHash":"a","choice":"snacks","confidence":0.9}';

      test('a first line that is not a header', () {
        expect(() => parseAisleLabels('$good\n'), _throwsFormatNamingLine(1));
        expect(() => parseAisleLabels('nope\n'), _throwsFormatNamingLine(1));
      });

      test('a wrong format', () {
        expect(
          () => parseAisleLabels(
            '{"format":"other","formatVersion":1,"questionHash":"q",'
            '"model":"m","modelDigest":"d"}\n',
          ),
          _throwsFormatNamingLine(1),
        );
      });

      test('a wrong formatVersion', () {
        expect(
          () => parseAisleLabels(
            '{"format":"perennia-open-food-facts-aisle-labels",'
            '"formatVersion":2,"questionHash":"q","model":"m",'
            '"modelDigest":"d"}\n',
          ),
          _throwsFormatNamingLine(1),
        );
      });

      test('a header field that is missing or not text', () {
        for (final key in const ['questionHash', 'model', 'modelDigest']) {
          final json = jsonDecode(_headerLine) as Map<String, Object?>;
          final missing = {...json}..remove(key);
          final wrong = {...json, key: 1};

          expect(
            () => parseAisleLabels('${jsonEncode(missing)}\n'),
            _throwsFormatNamingLine(1),
          );
          expect(
            () => parseAisleLabels('${jsonEncode(wrong)}\n'),
            _throwsFormatNamingLine(1),
          );
        }
      });

      test('a missing key', () {
        expect(
          () => parseAisleLabels(
            '$_headerLine\n{"code":"1","inputHash":"a","choice":"snacks"}\n',
          ),
          _throwsFormatNamingLine(2),
        );
      });

      test('an extra key', () {
        expect(
          () => parseAisleLabels(
            '$_headerLine\n'
            '{"code":"1","inputHash":"a","choice":"snacks","confidence":0.9,'
            '"x":1}\n',
          ),
          _throwsFormatNamingLine(2),
        );
      });

      test('an unknown choice', () {
        expect(
          () => parseAisleLabels(
            '$_headerLine\n'
            '{"code":"1","inputHash":"a","choice":"frozen","confidence":0.9}\n',
          ),
          _throwsFormatNamingLine(2),
        );
      });

      test('a confidence outside 0 to 1, or not a number', () {
        for (final confidence in const ['-0.1', '1.1', '"0.9"']) {
          expect(
            () => parseAisleLabels(
              '$_headerLine\n'
              '{"code":"1","inputHash":"a","choice":"snacks",'
              '"confidence":$confidence}\n',
            ),
            _throwsFormatNamingLine(2),
          );
        }
      });

      test('a repeated code, on the line that repeats it', () {
        expect(
          () => parseAisleLabels('$_headerLine\n$good\n$good\n'),
          _throwsFormatNamingLine(3),
        );
      });
    });
  });

  group('reference CSV', () {
    const columns = 'code,name,brand,categories,aisle,sampled_as,set';

    test('writes the columns, LF rows, a trailing newline, sorted by code', () {
      final csv = encodeAisleReference([
        _row(
          '2',
          name: 'Two',
          brand: '',
          categories: const [],
          answer: ReferenceAnswer.none,
          sampledAs: ReferenceDraw.noAisle,
          set: ReferenceSet.dev,
        ),
        _row(
          '1',
          name: 'One',
          brand: 'B',
          categories: const ['en:a', 'en:b'],
          aisle: FoodAisle.dairyEggs,
          sampledAs: ReferenceDraw.aisle,
        ),
      ]);

      expect(
        csv,
        '$columns\n'
        '1,One,B,en:a en:b,dairyEggs,aisle,test\n'
        '2,Two,,,none,noAisle,dev\n',
      );
    });

    test('an empty set is its header row', () {
      expect(encodeAisleReference(const []), '$columns\n');
      expect(
          parseAisleReference('$columns\n', allowUnlabelled: false), isEmpty);
    });

    test('quotes commas, quotes and line breaks, and reads them back', () {
      const name = 'Oats, "rolled"\nwith\r\nbreaks';

      final csv = encodeAisleReference([_row('1', name: name)]);
      expect(
        csv,
        '$columns\n'
        '1,"Oats, ""rolled""\nwith\r\nbreaks",A brand,en:foods,,random,test\n',
      );
      expect(
        parseAisleReference(csv, allowUnlabelled: true).single.name,
        name,
      );
    });

    test('prefixes formula cells with a quote and removes it on parse', () {
      for (final start in const ['=', '+', '-', '@', '\t', '\r']) {
        final name = '${start}1+1';
        final brand = '${start}brand';

        final csv = encodeAisleReference([_row('1', name: name, brand: brand)]);
        final cells = csv.split('\n')[1];
        expect(cells, contains("'$name"), reason: 'start ${start.codeUnits}');
        expect(cells, contains("'$brand"), reason: 'start ${start.codeUnits}');

        final row = parseAisleReference(csv, allowUnlabelled: true).single;
        expect(row.name, name);
        expect(row.brand, brand);
      }
    });

    test('keeps a quote that protects nothing', () {
      const csv = "$columns\n1,'tis the season,'b,en:a,,random,test\n";

      final row = parseAisleReference(csv, allowUnlabelled: true).single;

      expect(row.name, "'tis the season");
      expect(row.brand, "'b");
    });

    test('does not prefix text that is not a formula', () {
      final csv = encodeAisleReference([_row('1', name: 'Plain', brand: '')]);

      expect(csv, contains('1,Plain,,'));
    });

    test('reads every answer', () {
      final rows = parseAisleReference(
        '$columns\n'
        '1,n,b,en:a,snacks,random,test\n'
        '2,n,b,en:a,none,aisle,dev\n'
        '3,n,b,en:a,unsure,noAisle,dev\n',
        allowUnlabelled: false,
      );

      expect(rows[0].answer, ReferenceAnswer.aisle);
      expect(rows[0].aisle, FoodAisle.snacks);
      expect(rows[0].sampledAs, ReferenceDraw.random);
      expect(rows[0].set, ReferenceSet.test);
      expect(rows[1].answer, ReferenceAnswer.none);
      expect(rows[1].aisle, isNull);
      expect(rows[1].sampledAs, ReferenceDraw.aisle);
      expect(rows[1].set, ReferenceSet.dev);
      expect(rows[2].answer, ReferenceAnswer.unsure);
      expect(rows[2].aisle, isNull);
      expect(rows[2].sampledAs, ReferenceDraw.noAisle);
    });

    test('splits categories on single spaces, and empty is no tags', () {
      final rows = parseAisleReference(
        '$columns\n'
        '1,n,b,en:a en:b,,random,test\n'
        '2,n,b,,,random,test\n',
        allowUnlabelled: true,
      );

      expect(rows[0].categories, ['en:a', 'en:b']);
      expect(rows[1].categories, isEmpty);
    });

    test('an empty aisle is rejected strictly and unlabelled leniently', () {
      const csv = '$columns\n1,n,b,en:a,,random,test\n';

      expect(
        parseAisleReference(csv, allowUnlabelled: true).single.answer,
        ReferenceAnswer.unlabelled,
      );
      expect(
        () => parseAisleReference(csv, allowUnlabelled: false),
        _throwsFormatNamingLine(2),
      );
    });

    group('rejects, leniently too,', () {
      void expectRejected(String csv, int line) {
        expect(
          () => parseAisleReference(csv, allowUnlabelled: true),
          _throwsFormatNamingLine(line),
        );
      }

      test('an unknown column set', () {
        expectRejected('code,name\n', 1);
        expectRejected('$columns,extra\n', 1);
        expectRejected('name,code,brand,categories,aisle,sampled_as,set\n', 1);
      });

      test('empty text, which has no header row', () {
        expectRejected('', 1);
      });

      test('an unknown aisle, sampled_as or set', () {
        expectRejected('$columns\n1,n,b,en:a,frozen,random,test\n', 2);
        expectRejected('$columns\n1,n,b,en:a,,other,test\n', 2);
        expectRejected('$columns\n1,n,b,en:a,,random,train\n', 2);
      });

      test('the wrong number of cells', () {
        expectRejected('$columns\n1,n,b\n', 2);
      });

      test('a repeated code, on the line that repeats it', () {
        expectRejected(
          '$columns\n'
          '1,n,b,en:a,,random,test\n'
          '1,n,b,en:a,,random,dev\n',
          3,
        );
      });

      test('a later row, counting line breaks inside quoted cells', () {
        expectRejected(
          '$columns\n'
          '1,"two\nlines",b,en:a,,random,test\n'
          '2,n,b,en:a,frozen,random,test\n',
          4,
        );
      });
    });
  });

  group('isCurrentLabel', () {
    final header = AisleLabelsHeader(
      questionHash: aisleQuestionHash(),
      model: 'clef:latest',
      modelDigest: 'd1',
    );

    test('a matching input hash and question is current', () {
      expect(isCurrentLabel(_label(null, hash: 'a'), header, 'a'), isTrue);
    });

    test('a changed input hash is stale', () {
      expect(isCurrentLabel(_label(null, hash: 'a'), header, 'b'), isFalse);
    });

    test('a changed question hash is stale', () {
      expect(isCurrentLabel(_label(null, hash: 'a'), _header, 'a'), isFalse);
    });

    test('no header or no label is stale', () {
      expect(isCurrentLabel(_label(null, hash: 'a'), null, 'a'), isFalse);
      expect(isCurrentLabel(null, header, 'a'), isFalse);
    });
  });

  group('resolveFoodAisle', () {
    final confident = _label(FoodAisle.snacks, confidence: 0.99);

    test('a reference Aisle beats a confident label', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          reference: _row('1', aisle: FoodAisle.pantry),
        ),
        FoodAisle.pantry,
      );
    });

    test('a reference none gives no Aisle even with a confident label', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          reference: _row('1', answer: ReferenceAnswer.none),
        ),
        isNull,
      );
    });

    test('unsure and unlabelled rows fall through to the label', () {
      for (final answer in const [
        ReferenceAnswer.unsure,
        ReferenceAnswer.unlabelled,
      ]) {
        expect(
          resolveFoodAisle(
            currentLabel: confident,
            reference: _row('1', answer: answer),
          ),
          FoodAisle.snacks,
        );
      }
    });

    test('keeps a label at the threshold and drops one just below', () {
      expect(
        resolveFoodAisle(
          currentLabel: _label(FoodAisle.snacks, confidence: 0.6),
        ),
        FoodAisle.snacks,
      );
      expect(
        resolveFoodAisle(
          currentLabel: _label(FoodAisle.snacks, confidence: 0.599),
        ),
        isNull,
      );
    });

    test('other gives no Aisle', () {
      expect(
        resolveFoodAisle(currentLabel: _label(null, confidence: 0.99)),
        isNull,
      );
    });

    test('no current label gives no Aisle', () {
      expect(resolveFoodAisle(currentLabel: null), isNull);
    });
  });

  group('resolveAisleBundle', () {
    test('gives one product per input line, in input order', () {
      final bundle = resolveAisleBundle(
        input: [_line('2', scans: 5), _line('1', scans: 9)],
        labels: {
          '1': _label(FoodAisle.snacks),
          '2': _label(FoodAisle.drinks),
        },
        reference: const [],
      );

      expect(bundle, [
        (code: '2', scans: 5, aisle: FoodAisle.drinks),
        (code: '1', scans: 9, aisle: FoodAisle.snacks),
      ]);
    });

    test('a code with no label gets only the reference step', () {
      final bundle = resolveAisleBundle(
        input: [_line('1'), _line('2')],
        labels: const {},
        reference: [_row('1', aisle: FoodAisle.pantry)],
      );

      expect(bundle[0].aisle, FoodAisle.pantry);
      expect(bundle[1].aisle, isNull);
    });
  });

  group('reusableLabels, labelsToMake and mergeLabels', () {
    AisleLabels source(
      Map<String, AisleLabel> byCode, {
      String questionHash = 'q1',
      String modelDigest = 'd1',
    }) {
      return AisleLabels(
        header: AisleLabelsHeader(
          questionHash: questionHash,
          model: 'clef:latest',
          modelDigest: modelDigest,
        ),
        byCode: byCode,
      );
    }

    Map<String, AisleLabel> reuse(List<AisleLabels> sources) {
      return reusableLabels(
        [_line('1', hash: 'a'), _line('2', hash: 'b')],
        sources,
        questionHash: 'q1',
        modelDigest: 'd1',
      );
    }

    test('reuses a label only when question, digest and input hash match', () {
      final reused = reuse([
        source({
          '1': _label(FoodAisle.snacks, hash: 'a'),
          '2': _label(FoodAisle.snacks, hash: 'stale'),
          'gone': _label(FoodAisle.snacks, hash: 'x'),
        }),
      ]);

      expect(reused.keys, ['1']);
    });

    test('a source under another question gives nothing', () {
      final reused = reuse([
        source({'1': _label(FoodAisle.snacks, hash: 'a')}, questionHash: 'q2'),
      ]);

      expect(reused, isEmpty);
    });

    test('a source with another model digest gives nothing', () {
      final reused = reuse([
        source({'1': _label(FoodAisle.snacks, hash: 'a')}, modelDigest: 'd2'),
      ]);

      expect(reused, isEmpty);
    });

    test('no file gives nothing', () {
      expect(reuse([parseAisleLabels('')]), isEmpty);
    });

    test('a checkpoint label wins over a committed one', () {
      final reused = reuse([
        source({'1': _label(FoodAisle.snacks, hash: 'a')}),
        source({'1': _label(FoodAisle.drinks, hash: 'a')}),
      ]);

      expect(reused['1']!.aisle, FoodAisle.drinks);
    });

    test('a stale checkpoint label leaves the committed one', () {
      final reused = reuse([
        source({'1': _label(FoodAisle.snacks, hash: 'a')}),
        source({'1': _label(FoodAisle.drinks, hash: 'stale')}),
      ]);

      expect(reused['1']!.aisle, FoodAisle.snacks);
    });

    test('labelsToMake returns the lines with no reusable label', () {
      final toMake = labelsToMake(
        [_line('1'), _line('2'), _line('3')],
        {'2': _label(null)},
      );

      expect(toMake.map((line) => line.code), ['1', '3']);
    });

    test('in a merge a made label wins and codes out of the input drop', () {
      final merged = mergeLabels(
        input: [_line('1'), _line('2'), _line('3')],
        reused: {
          '1': _label(FoodAisle.snacks),
          '2': _label(FoodAisle.snacks),
          'gone': _label(FoodAisle.snacks),
        },
        made: {'2': _label(FoodAisle.drinks), 'alsoGone': _label(null)},
        header: _header,
      );

      expect(merged.header, same(_header));
      expect(merged.byCode.keys.toSet(), {'1', '2'});
      expect(merged.byCode['1']!.aisle, FoodAisle.snacks);
      expect(merged.byCode['2']!.aisle, FoodAisle.drinks);
    });
  });

  group('sampleReference', () {
    /// [perAisle] products predicted as each Aisle and [noAisle] with no
    /// prediction, with distinct scans that fall as the code rises.
    ({List<AisleInputLine> input, Map<String, AisleLabel> labels}) fixture({
      Map<FoodAisle, int> perAisle = const {},
      int noAisle = 0,
    }) {
      final input = <AisleInputLine>[];
      final labels = <String, AisleLabel>{};
      var number = 0;
      void add(FoodAisle? aisle) {
        final code = _code(number);
        input.add(_line(code, scans: 100000 - number));
        labels[code] = _label(aisle);
        number += 1;
      }

      perAisle.forEach((aisle, count) {
        for (var i = 0; i < count; i += 1) {
          add(aisle);
        }
      });
      for (var i = 0; i < noAisle; i += 1) {
        add(null);
      }
      return (input: input, labels: labels);
    }

    Iterable<AisleReferenceRow> cell(
      List<AisleReferenceRow> rows,
      ReferenceSet set,
      ReferenceDraw draw,
    ) {
      return rows.where((row) => row.set == set && row.sampledAs == draw);
    }

    test('the same seed gives the same rows, another seed different ones', () {
      final data = fixture(
        perAisle: {FoodAisle.snacks: 300, FoodAisle.drinks: 200},
        noAisle: 300,
      );

      List<String> sample(int seed) {
        return [
          for (final row in sampleReference(
            input: data.input,
            labels: data.labels,
            existing: const [],
            seed: seed,
          ))
            '${row.code}/${row.set.name}/${row.sampledAs.name}',
        ];
      }

      expect(sample(1), sample(1));
      expect(sample(1), isNot(sample(2)));
    });

    test('does not depend on the order of the input', () {
      final data = fixture(perAisle: {FoodAisle.snacks: 300}, noAisle: 100);

      List<String> sample(List<AisleInputLine> input) {
        return [
          for (final row in sampleReference(
            input: input,
            labels: data.labels,
            existing: const [],
            seed: 3,
          ))
            row.code,
        ];
      }

      expect(sample(data.input.reversed.toList()), sample(data.input));
    });

    test('draws in the spec\'s order, every cell its full count', () {
      final data = fixture(
        perAisle: {FoodAisle.dairyEggs: 400, FoodAisle.babyFood: 400},
        noAisle: 300,
      );

      final rows = sampleReference(
        input: data.input,
        labels: data.labels,
        existing: const [],
        seed: 1,
      );

      final order = <String>[];
      for (final row in rows) {
        final name = '${row.set.name} ${row.sampledAs.name}';
        final aisle = row.sampledAs == ReferenceDraw.aisle
            ? ' ${data.labels[row.code]!.aisle!.name}'
            : '';
        if (order.isEmpty || order.last != '$name$aisle') {
          order.add('$name$aisle');
        }
      }
      expect(order, [
        'test random',
        'dev random',
        // Browse rows, then rows outside Browse, are one run of test rows.
        'test aisle dairyEggs',
        'dev aisle dairyEggs',
        'test aisle babyFood',
        'dev aisle babyFood',
        'dev noAisle',
      ]);
      expect(rows.length, 120 + 100 + 2 * (15 + 15 + 5) + 10);
      // The first Aisle's test rows: Browse rows, then rows outside Browse.
      // Its 100 most scanned products are codes 000000 to 000099.
      final firstAisleTest = rows.skip(220).take(30).map(
            (row) => int.parse(row.code),
          );
      expect(firstAisleTest.take(15).every((code) => code < 100), isTrue);
      expect(firstAisleTest.skip(15).every((code) => code >= 100), isTrue);
      expect(
        rows.map((row) => row.code).toSet().length,
        rows.length,
        reason: 'no product is drawn twice',
      );
      expect(
        rows.every((row) => row.answer == ReferenceAnswer.unlabelled),
        isTrue,
      );
    });

    test('new rows carry the input\'s name, brand and tags', () {
      const line = AisleInputLine(
        code: '1',
        name: 'Oats',
        brand: 'Acme',
        categories: ['en:cereals'],
        scans: 1,
        inputHash: 'h',
      );

      final rows = sampleReference(
        input: const [line],
        labels: const {},
        existing: const [],
        seed: 1,
      );

      expect(rows.single.name, 'Oats');
      expect(rows.single.brand, 'Acme');
      expect(rows.single.categories, ['en:cereals']);
      expect(rows.single.aisle, isNull);
    });

    test('a missing brand is empty text', () {
      final rows = sampleReference(
        input: [_line('1')],
        labels: const {},
        existing: const [],
        seed: 1,
      );

      expect(rows.single.brand, '');
    });

    test('random rows are uniform over the input', () {
      // A quarter of the input has a prediction. Across seeds, random rows
      // must hold about a quarter of them, whatever the Aisle cells want.
      final data = fixture(perAisle: {FoodAisle.snacks: 250}, noAisle: 750);
      var predicted = 0;
      var drawn = 0;

      for (var seed = 0; seed < 20; seed += 1) {
        final rows = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: const [],
          seed: seed,
        );
        for (final row in rows.take(220)) {
          expect(row.sampledAs, ReferenceDraw.random);
          drawn += 1;
          if (data.labels[row.code]!.aisle != null) {
            predicted += 1;
          }
        }
      }

      expect(predicted / drawn, closeTo(0.25, 0.03));
    });

    test('splits an Aisle\'s test rows into Browse and outside it', () {
      final data = fixture(perAisle: {FoodAisle.snacks: 130});
      // The random cells are full, so they leave the snacks to the Aisle cells.
      final existingRandom = [
        for (var i = 0; i < referenceTestRandomRows; i += 1)
          _row('t$i', sampledAs: ReferenceDraw.random),
        for (var i = 0; i < referenceDevRandomRows; i += 1)
          _row('d$i', sampledAs: ReferenceDraw.random, set: ReferenceSet.dev),
      ];

      final rows = sampleReference(
        input: [
          ...data.input,
          for (final row in existingRandom) _line(row.code, scans: 0),
        ],
        labels: data.labels,
        existing: existingRandom,
        seed: 1,
      );

      final aisleRows = cell(rows, ReferenceSet.test, ReferenceDraw.aisle);
      expect(aisleRows.length, 30);
      // Codes 000000 to 000099 are the 100 most scanned snacks.
      expect(aisleRows.where((row) => int.parse(row.code) < 100).length, 15);
    });

    group('tops up', () {
      // Enough products that no cell is short of candidates, with the random
      // cells already full so that only the cell under test draws.
      final data = fixture(
        perAisle: {FoodAisle.snacks: 300},
        noAisle: 200,
      );
      final fullRandom = <AisleReferenceRow>[
        for (var i = 0; i < referenceTestRandomRows; i += 1)
          _row('x-t$i', sampledAs: ReferenceDraw.random),
        for (var i = 0; i < referenceDevRandomRows; i += 1)
          _row('x-d$i', sampledAs: ReferenceDraw.random, set: ReferenceSet.dev),
      ];
      final filler = [
        for (final row in fullRandom) _line(row.code, scans: 0),
      ];

      List<AisleReferenceRow> top(List<AisleReferenceRow> existing) {
        return sampleReference(
          input: [...data.input, ...filler],
          labels: data.labels,
          existing: [...fullRandom, ...existing],
          seed: 5,
        );
      }

      test('only a Browse cell\'s shortfall, from rows of any sampled_as', () {
        // Snack 000000 is in Browse. Three rows, however they were drawn.
        final rows = top([
          _row('000000', sampledAs: ReferenceDraw.random),
          _row('000001', sampledAs: ReferenceDraw.aisle),
          _row('000002', sampledAs: ReferenceDraw.noAisle),
        ]);

        final browse = rows.where(
          (row) => row.set == ReferenceSet.test && int.parse(row.code) < 100,
        );
        expect(browse.length, 12);
      });

      test('a cell outside Browse counts only rows outside Browse', () {
        final rows = top([
          _row('000000', sampledAs: ReferenceDraw.aisle),
          _row('000150', sampledAs: ReferenceDraw.aisle),
        ]);

        final testRows = cell(rows, ReferenceSet.test, ReferenceDraw.aisle);
        expect(
          testRows.where((row) => int.parse(row.code) < 100).length,
          14,
        );
        expect(
          testRows.where((row) => int.parse(row.code) >= 100).length,
          14,
        );
      });

      test('a test row does not count toward a dev cell', () {
        final rows = top([
          _row('000000', sampledAs: ReferenceDraw.aisle),
        ]);

        expect(cell(rows, ReferenceSet.dev, ReferenceDraw.aisle).length, 5);
      });

      test('a dev cell counts dev rows of any sampled_as', () {
        final rows = top([
          _row(
            '000000',
            sampledAs: ReferenceDraw.noAisle,
            set: ReferenceSet.dev,
          ),
          _row(
            '000001',
            sampledAs: ReferenceDraw.random,
            set: ReferenceSet.dev,
          ),
        ]);

        expect(cell(rows, ReferenceSet.dev, ReferenceDraw.aisle).length, 3);
      });

      test('a random dev row with no prediction counts toward noAisle', () {
        // Code 000300 is the first product with no prediction. No filler
        // here: filler rows have no prediction either, and would fill the cell.
        final rows = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: [
            _row(
              '000300',
              sampledAs: ReferenceDraw.random,
              set: ReferenceSet.dev,
            ),
          ],
          seed: 5,
        );

        expect(cell(rows, ReferenceSet.dev, ReferenceDraw.noAisle).length, 9);
      });

      test('a random cell counts only rows sampled as random', () {
        final rows = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: [
            _row('000000', sampledAs: ReferenceDraw.aisle),
            _row('000001', sampledAs: ReferenceDraw.random),
            _row(
              '000002',
              sampledAs: ReferenceDraw.random,
              set: ReferenceSet.dev,
            ),
          ],
          seed: 5,
        );

        expect(cell(rows, ReferenceSet.test, ReferenceDraw.random).length, 119);
        expect(cell(rows, ReferenceSet.dev, ReferenceDraw.random).length, 99);
      });

      test('a row that has left the input is in no cell, and is kept', () {
        final rows = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: [_row('gone', sampledAs: ReferenceDraw.random)],
          seed: 5,
        );

        expect(cell(rows, ReferenceSet.test, ReferenceDraw.random).length, 120);
        expect(rows.map((row) => row.code), isNot(contains('gone')));
      });

      test('nothing when the file already holds every cell', () {
        final first = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: const [],
          seed: 5,
        );

        final second = sampleReference(
          input: data.input,
          labels: data.labels,
          existing: first,
          seed: 6,
        );

        expect(second, isEmpty);
      });

      test('existing codes are skipped', () {
        final existing = [
          for (var i = 0; i < 50; i += 1)
            _row(_code(i), sampledAs: ReferenceDraw.noAisle),
        ];

        final rows = top(existing);

        final existingCodes = existing.map((row) => row.code).toSet();
        expect(
          rows.where((row) => existingCodes.contains(row.code)),
          isEmpty,
        );
      });

      test('ranks use the existing rows\' resolved Aisles', () {
        // A person moved the 90 most scanned snacks to pantry, so they leave
        // the snacks list, and products 100 to 189 enter its Browse rows.
        final moved = [
          for (var i = 0; i < 90; i += 1)
            _row(
              _code(i),
              aisle: FoodAisle.pantry,
              sampledAs: ReferenceDraw.noAisle,
              set: ReferenceSet.dev,
            ),
        ];

        final rows = top(moved);

        final testCodes = cell(
          rows,
          ReferenceSet.test,
          ReferenceDraw.aisle,
        ).map((row) => int.parse(row.code));
        expect(testCodes.where((code) => code >= 190).length, 15);
        expect(testCodes.where((code) => code < 190).length, 15);
      });
    });

    test('a cell with fewer eligible products takes all of them', () {
      final data = fixture(perAisle: {FoodAisle.snacks: 3}, noAisle: 2);

      final rows = sampleReference(
        input: data.input,
        labels: data.labels,
        existing: const [],
        seed: 1,
      );

      expect(rows.length, 5);
      expect(cell(rows, ReferenceSet.test, ReferenceDraw.random).length, 5);
    });

    test('a short Aisle cell takes all its products', () {
      final data = fixture(perAisle: {FoodAisle.snacks: 4});
      final filled = <AisleReferenceRow>[
        for (var i = 0; i < referenceTestRandomRows; i += 1)
          _row('x-t$i', sampledAs: ReferenceDraw.random),
        for (var i = 0; i < referenceDevRandomRows; i += 1)
          _row('x-d$i', sampledAs: ReferenceDraw.random, set: ReferenceSet.dev),
      ];

      final rows = sampleReference(
        input: [
          ...data.input,
          for (final row in filled) _line(row.code, scans: 0),
        ],
        labels: data.labels,
        existing: filled,
        seed: 1,
      );

      expect(rows.map((row) => row.code).toSet(), {
        '000000',
        '000001',
        '000002',
        '000003',
      });
      expect(cell(rows, ReferenceSet.test, ReferenceDraw.aisle).length, 4);
    });
  });

  group('buildAisleRanking and browseRank', () {
    final ranking = buildAisleRanking(const [
      (code: 'c', scans: 10, aisle: FoodAisle.snacks),
      (code: 'a', scans: 30, aisle: FoodAisle.snacks),
      (code: 'e', scans: 20, aisle: FoodAisle.snacks),
      (code: 'b', scans: 20, aisle: FoodAisle.snacks),
      (code: 'x', scans: 25, aisle: FoodAisle.drinks),
      (code: 'y', scans: 99, aisle: null),
    ]);

    test('the most scanned has rank 1', () {
      expect(browseRank(ranking, FoodAisle.snacks, code: 'a', scans: 30), 1);
    });

    test('orders by scans descending, then code ascending', () {
      expect(browseRank(ranking, FoodAisle.snacks, code: 'b', scans: 20), 2);
      expect(browseRank(ranking, FoodAisle.snacks, code: 'e', scans: 20), 3);
      expect(browseRank(ranking, FoodAisle.snacks, code: 'c', scans: 10), 4);
      expect(
        ranking.listOf(FoodAisle.snacks).map((product) => product.code),
        ['a', 'b', 'e', 'c'],
      );
    });

    test('ranks a product from another Aisle as if it were in this one', () {
      expect(browseRank(ranking, FoodAisle.snacks, code: 'x', scans: 25), 2);
      expect(browseRank(ranking, FoodAisle.snacks, code: 'y', scans: 99), 1);
      expect(browseRank(ranking, FoodAisle.snacks, code: 'z', scans: 1), 5);
    });

    test('that leaves the others\' ranks where they were', () {
      browseRank(ranking, FoodAisle.snacks, code: 'x', scans: 25);

      expect(browseRank(ranking, FoodAisle.snacks, code: 'e', scans: 20), 3);
      expect(ranking.listOf(FoodAisle.snacks).length, 4);
    });

    test('an empty Aisle ranks anything first', () {
      expect(browseRank(ranking, FoodAisle.pantry, code: 'a', scans: 1), 1);
      expect(ranking.listOf(FoodAisle.pantry), isEmpty);
    });
  });

  group('measureAisleLabels', () {
    test('a hand-built fixture has the known measures', () {
      final fixture = _MeasureFixture();
      // Random, test: 4 predicted (3 right), 1 predicted none.
      for (final (predicted, person) in const [
        (FoodAisle.snacks, FoodAisle.snacks),
        (FoodAisle.snacks, FoodAisle.snacks),
        (FoodAisle.drinks, FoodAisle.drinks),
        (FoodAisle.drinks, FoodAisle.snacks),
        (null, FoodAisle.snacks),
      ]) {
        fixture.row(
          predicted,
          person: person,
          sampledAs: ReferenceDraw.random,
        );
      }
      // Predicted, person says no Aisle: agreement is wrong, not in coverage.
      fixture.row(
        FoodAisle.pantry,
        person: null,
        sampledAs: ReferenceDraw.random,
      );

      final measures = fixture.measure().test;

      expect(measures.agreement, (matched: 3, rows: 5));
      expect(measures.coverage, (matched: 4, rows: 5));
      expect(measures.browsePrecision[FoodAisle.snacks], (matched: 2, rows: 2));
      expect(measures.browsePrecision[FoodAisle.drinks], (matched: 1, rows: 2));
      expect(measures.browsePrecision[FoodAisle.pantry], (matched: 0, rows: 1));
      expect(measures.recall[FoodAisle.snacks], (matched: 2, rows: 4));
      expect(measures.recall[FoodAisle.drinks], (matched: 1, rows: 1));
    });

    test('outside-Browse precision counts rows past the limit', () {
      final fixture = _MeasureFixture()..fillBrowse(FoodAisle.snacks);
      fixture.row(FoodAisle.snacks, person: FoodAisle.snacks);
      fixture.row(FoodAisle.snacks, person: FoodAisle.drinks);

      final measures = fixture.measure().test;

      expect(measures.precision[FoodAisle.snacks], (matched: 1, rows: 2));
      expect(measures.browsePrecision[FoodAisle.snacks], (matched: 0, rows: 0));
    });

    test('precision counts rows of any sampled_as', () {
      final fixture = _MeasureFixture()
        ..row(FoodAisle.snacks, person: FoodAisle.snacks)
        ..row(
          FoodAisle.snacks,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.random,
        )
        ..row(
          FoodAisle.snacks,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.noAisle,
        );

      final measures = fixture.measure().test;

      expect(measures.browsePrecision[FoodAisle.snacks], (matched: 3, rows: 3));
      expect(measures.agreement.rows, 1);
    });

    test('the threshold decides a prediction, not the bundle\'s Aisle', () {
      final fixture = _MeasureFixture();
      final code = fixture.product(FoodAisle.snacks, confidence: 0.599);
      fixture.reference.add(
        _row(code, aisle: FoodAisle.snacks, sampledAs: ReferenceDraw.random),
      );

      final measures = fixture.measure().test;

      expect(measures.agreement.rows, 0);
      expect(measures.coverage, (matched: 0, rows: 1));
    });

    test('a person\'s own answer is not the prediction', () {
      // Resolved as drinks from the person's answer, but predicted as snacks.
      final fixture = _MeasureFixture()..fillBrowse(FoodAisle.drinks);
      fixture.product(FoodAisle.snacks);
      fixture.bundle.add((code: 'p', scans: 5, aisle: FoodAisle.drinks));
      fixture.labels['p'] = _label(FoodAisle.snacks);
      fixture.reference.add(
        _row('p', aisle: FoodAisle.drinks, sampledAs: ReferenceDraw.random),
      );

      final measures = fixture.measure().test;

      expect(measures.agreement, (matched: 0, rows: 1));
      expect(measures.browsePrecision[FoodAisle.snacks], (matched: 0, rows: 1));
      expect(measures.recall[FoodAisle.drinks], (matched: 0, rows: 1));
    });

    test('a product with no label line has no prediction', () {
      final fixture = _MeasureFixture();
      fixture.bundle.add((code: 'p', scans: 5, aisle: null));
      fixture.reference.add(
        _row('p', aisle: FoodAisle.snacks, sampledAs: ReferenceDraw.random),
      );

      final measures = fixture.measure().test;

      expect(measures.coverage, (matched: 0, rows: 1));
    });

    test('rows outside the bundle and unsure rows are not counted', () {
      final fixture = _MeasureFixture();
      final unsure = fixture.product(FoodAisle.snacks);
      final unlabelled = fixture.product(FoodAisle.snacks);
      fixture.reference.addAll([
        _row(unsure, answer: ReferenceAnswer.unsure),
        _row(unlabelled),
        _row('gone', aisle: FoodAisle.snacks),
        _row('gone2', answer: ReferenceAnswer.unsure),
        _row('gone3'),
      ]);

      final measures = fixture.measure().test;

      expect(measures.agreement.rows, 0);
      expect(measures.coverage.rows, 0);
      expect(measures.browsePrecision[FoodAisle.snacks]!.rows, 0);
      expect(measures.unsureRows, 1);
      expect(measures.unlabelledRows, 1);
    });

    test('each set is measured on its own', () {
      final fixture = _MeasureFixture()
        ..row(
          FoodAisle.snacks,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.random,
          set: ReferenceSet.dev,
        );

      final measures = fixture.measure();

      expect(measures.dev.agreement, (matched: 1, rows: 1));
      expect(measures.test.agreement.rows, 0);
    });

    test('a measure with no rows is not measured, in every Aisle', () {
      final measures = _MeasureFixture().measure();

      for (final set in [measures.dev, measures.test]) {
        expect(set.agreement.rows, 0);
        expect(set.coverage.rows, 0);
        for (final aisle in FoodAisle.values) {
          expect(set.browsePrecision[aisle], (matched: 0, rows: 0));
          expect(set.precision[aisle], (matched: 0, rows: 0));
          expect(set.recall[aisle], (matched: 0, rows: 0));
        }
      }
      expect(measures.failures, [
        'overall agreement: not measured',
        'overall coverage: not measured',
      ]);
    });

    test('only test-set failures are listed', () {
      final fixture = _MeasureFixture()
        ..row(
          FoodAisle.snacks,
          person: FoodAisle.drinks,
          sampledAs: ReferenceDraw.random,
          set: ReferenceSet.dev,
        )
        ..row(
          FoodAisle.snacks,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.random,
        );

      // The dev row's wrong answer fails nothing; its product still counts in
      // the snacks list, which is what the one row needed counts.
      expect(fixture.measure().failures, [
        'too few rows for snacks in Browse: 1 of 2',
      ]);
    });

    group('the failure texts', () {
      test('overall agreement below the bar', () {
        final fixture = _MeasureFixture();
        for (var i = 0; i < 105; i += 1) {
          fixture.row(
            FoodAisle.snacks,
            person: i < 98 ? FoodAisle.snacks : FoodAisle.drinks,
            sampledAs: ReferenceDraw.random,
            scans: 1000,
          );
        }

        expect(
          fixture.measure().failures,
          contains('overall agreement 93.3% is below 95.0% (n=105)'),
        );
      });

      test('overall agreement and coverage with no rows', () {
        final failures = _MeasureFixture().measure().failures;

        expect(failures, contains('overall agreement: not measured'));
        expect(failures, contains('overall coverage: not measured'));
      });

      test('overall coverage below the bar', () {
        final fixture = _MeasureFixture();
        for (var i = 0; i < 110; i += 1) {
          fixture.row(
            i < 88 ? FoodAisle.snacks : null,
            person: FoodAisle.snacks,
            sampledAs: ReferenceDraw.random,
          );
        }

        expect(
          fixture.measure().failures,
          contains('overall coverage 80.0% is below 85.0% (n=110)'),
        );
      });

      test('too few rows in Browse', () {
        final fixture = _MeasureFixture()
          ..browseRows(FoodAisle.drinks, matched: 12, rows: 12);
        for (var i = 0; i < 3; i += 1) {
          fixture.product(FoodAisle.drinks);
        }

        expect(
          fixture.measure().failures,
          contains('too few rows for drinks in Browse: 12 of 15'),
        );
      });

      test('browse precision below the bar', () {
        final fixture = _MeasureFixture()
          ..browseRows(FoodAisle.snacks, matched: 13, rows: 15);

        expect(
          fixture.measure().failures,
          contains('browse precision for snacks 86.7% is below 90.0% (n=15)'),
        );
      });

      test('too few rows outside Browse, the required count the part\'s size',
          () {
        final fixture = _MeasureFixture()..fillBrowse(FoodAisle.babyFood);
        for (var i = 0; i < 3; i += 1) {
          fixture.row(FoodAisle.babyFood, person: FoodAisle.babyFood);
        }
        for (var i = 0; i < 6; i += 1) {
          fixture.product(FoodAisle.babyFood);
        }

        expect(
          fixture.measure().failures,
          contains('too few rows for babyFood outside Browse: 3 of 9'),
        );
      });

      test('precision outside Browse below the bar', () {
        final fixture = _MeasureFixture()..fillBrowse(FoodAisle.snacks);
        for (var i = 0; i < 21; i += 1) {
          fixture.row(
            FoodAisle.snacks,
            person: i < 18 ? FoodAisle.snacks : FoodAisle.drinks,
          );
        }

        expect(
          fixture.measure().failures,
          contains(
            'precision for snacks outside Browse 85.7% is below 90.0% (n=21)',
          ),
        );
      });
    });

    test('lists failures in order: overall, then each Aisle\'s four', () {
      final fixture = _MeasureFixture();
      // Agreement 1 of 2 and coverage 1 of 2, from pantry's own rows.
      fixture
        ..row(
          FoodAisle.pantry,
          person: FoodAisle.pantry,
          sampledAs: ReferenceDraw.random,
          scans: 1000,
        )
        ..row(
          FoodAisle.pantry,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.random,
          scans: 1000,
        )
        ..row(
          null,
          person: FoodAisle.snacks,
          sampledAs: ReferenceDraw.random,
          scans: 1000,
        );
      // dairyEggs: too few in Browse, precision failing outside it.
      fixture.fillBrowse(FoodAisle.dairyEggs);
      for (var i = 0; i < 15; i += 1) {
        fixture.row(
          FoodAisle.dairyEggs,
          person: i == 0 ? FoodAisle.dairyEggs : FoodAisle.drinks,
        );
      }
      // snacks: browse precision failing, too few outside it.
      fixture.browseRows(FoodAisle.snacks, matched: 0, rows: 15);
      for (var i = 0; i < 85; i += 1) {
        fixture.product(FoodAisle.snacks, scans: 1000);
      }
      fixture.product(FoodAisle.snacks);

      expect(fixture.measure().failures, [
        'overall agreement 50.0% is below 95.0% (n=2)',
        'overall coverage 66.7% is below 85.0% (n=3)',
        'too few rows for dairyEggs in Browse: 0 of 15',
        'precision for dairyEggs outside Browse 6.7% is below 90.0% (n=15)',
        'browse precision for pantry 50.0% is below 90.0% (n=2)',
        'browse precision for snacks 0.0% is below 90.0% (n=15)',
        'too few rows for snacks outside Browse: 0 of 1',
      ]);
    });

    test('a share just under a bar fails although it prints as the bar', () {
      final fixture = _MeasureFixture();
      for (var i = 0; i < 199; i += 1) {
        fixture.row(
          FoodAisle.snacks,
          person: i < 189 ? FoodAisle.snacks : FoodAisle.drinks,
          sampledAs: ReferenceDraw.random,
        );
      }

      expect(
        fixture.measure().failures,
        contains('overall agreement 95.0% is below 95.0% (n=199)'),
      );
    });

    test('a share exactly at a bar passes', () {
      final fixture = _MeasureFixture();
      for (var i = 0; i < 20; i += 1) {
        fixture.row(
          FoodAisle.snacks,
          person: i < 19 ? FoodAisle.snacks : FoodAisle.drinks,
          sampledAs: ReferenceDraw.random,
        );
      }

      final failures = fixture.measure().failures;

      expect(failures.where((text) => text.startsWith('overall agreement')),
          isEmpty);
    });

    test('a part with too few rows gives only the too few rows failure', () {
      final fixture = _MeasureFixture()
        ..browseRows(FoodAisle.snacks, matched: 0, rows: 14);
      fixture.product(FoodAisle.snacks);

      final failures =
          fixture.measure().failures.where((text) => text.contains('snacks'));

      expect(failures, ['too few rows for snacks in Browse: 14 of 15']);
    });

    test('a required count of 0 is no failure, and is not measured', () {
      // Exactly 100 snacks, and a row predicted as snacks but resolved
      // elsewhere that ranks just past them: the snacks have no products
      // outside Browse, so the part is not measured.
      final fixture = _MeasureFixture()..fillBrowse(FoodAisle.snacks);
      fixture.bundle.add((code: 'p', scans: 1, aisle: FoodAisle.drinks));
      fixture.labels['p'] = _label(FoodAisle.snacks);
      fixture.reference.add(_row('p', aisle: FoodAisle.drinks));

      final measures = fixture.measure();

      expect(measures.test.precision[FoodAisle.snacks], (matched: 0, rows: 0));
      expect(
        measures.failures.where(
          (text) => text.contains('snacks') && text.contains('outside'),
        ),
        isEmpty,
      );
    });

    test('a required count under the minimum is enough once met', () {
      final fixture = _MeasureFixture()
        ..browseRows(FoodAisle.babyFood, matched: 3, rows: 3);

      expect(
        fixture.measure().failures.where((text) => text.contains('babyFood')),
        isEmpty,
      );
    });
  });

  group('descriptions', () {
    test('every FoodAisle has one', () {
      for (final aisle in FoodAisle.values) {
        expect(aisleModelDescriptions[aisle], isNotEmpty, reason: aisle.name);
      }
      expect(aisleModelDescriptions.length, FoodAisle.values.length);
    });

    test('none says "goes to": a description names only its own foods', () {
      for (final description in aisleModelDescriptions.values) {
        expect(description.toLowerCase(), isNot(contains('goes to')));
      }
    });
  });

  group('aisleGuideText', () {
    test('contains every principle and every description, in order', () {
      final guide = aisleGuideText();

      var position = 0;
      for (final text in [
        ...aislePrinciples,
        for (final aisle in FoodAisle.values) aisleModelDescriptions[aisle]!,
      ]) {
        final found = guide.indexOf(text, position);
        expect(found, greaterThanOrEqualTo(position), reason: text);
        position = found + text.length;
      }
    });

    test('names each Aisle\'s id and UI label, and the other answers', () {
      final guide = aisleGuideText();

      for (final aisle in FoodAisle.values) {
        expect(guide, contains('${aisle.name} (${aisle.label})'));
      }
      expect(guide, contains('none:'));
      expect(guide, contains('unsure:'));
    });
  });
}
