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

AisleOverrideRow _override(
  String code, {
  AisleOverrideAnswer answer = AisleOverrideAnswer.none,
  FoodAisle? aisle,
  String name = 'A name',
  String brand = 'A brand',
  List<String> categories = const ['en:foods'],
}) {
  return AisleOverrideRow(
    code: code,
    name: name,
    brand: brand,
    categories: categories,
    answer: aisle == null ? answer : AisleOverrideAnswer.aisle,
    aisle: aisle,
  );
}

/// Labels under the current question.
AisleLabels _currentLabels(Map<String, AisleLabel> byCode) {
  return AisleLabels(
    header: AisleLabelsHeader(
      questionHash: aisleQuestionHash(),
      model: 'clef:latest',
      modelDigest: 'd1',
    ),
    byCode: byCode,
  );
}

/// Second opinions under the current question.
AisleSecondOpinions _currentOpinions(
  Map<String, AisleSecondOpinion> byCode, {
  String model = 'claude-haiku-5-5',
}) {
  return AisleSecondOpinions(
    header: AisleSecondOpinionsHeader(
      questionHash: aisleQuestionHash(),
      model: model,
    ),
    byCode: byCode,
  );
}

const _noOpinions = AisleSecondOpinions(header: null, byCode: {});

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

  group('second opinions file', () {
    const headerLine =
        '{"format":"perennia-open-food-facts-aisle-second-opinions",'
        '"formatVersion":1,"questionHash":"q1","model":"claude-haiku-5-5"}';
    const text = '$headerLine\n'
        '{"code":"1","inputHash":"a","choice":"dairyEggs"}\n'
        '{"code":"2","inputHash":"b","choice":"other"}\n';

    test('a sorted, compact file round-trips', () {
      final opinions = parseAisleSecondOpinions(text);

      expect(opinions.header!.questionHash, 'q1');
      expect(opinions.header!.model, 'claude-haiku-5-5');
      expect(
          opinions.byCode['1'], (inputHash: 'a', aisle: FoodAisle.dairyEggs));
      expect(opinions.byCode['2'], (inputHash: 'b', aisle: null));
      expect(encodeAisleSecondOpinions(opinions), text);
    });

    test('encoding sorts by code', () {
      final encoded = encodeAisleSecondOpinions(
        const AisleSecondOpinions(
          header: AisleSecondOpinionsHeader(
            questionHash: 'q1',
            model: 'claude-haiku-5-5',
          ),
          byCode: {
            '2': (inputHash: 'b', aisle: null),
            '1': (inputHash: 'a', aisle: FoodAisle.dairyEggs),
          },
        ),
      );

      expect(encoded, text);
    });

    test('an empty text is no file', () {
      final opinions = parseAisleSecondOpinions('');

      expect(opinions.header, isNull);
      expect(opinions.byCode, isEmpty);
      expect(encodeAisleSecondOpinions(opinions), '');
    });

    test('second opinions with no header cannot be written', () {
      expect(
        () => encodeAisleSecondOpinions(
          const AisleSecondOpinions(
            header: null,
            byCode: {'1': (inputHash: 'a', aisle: null)},
          ),
        ),
        throwsArgumentError,
      );
    });

    group('rejects', () {
      const good = '{"code":"1","inputHash":"a","choice":"snacks"}';

      void expectRejected(String text, int line) {
        expect(
          () => parseAisleSecondOpinions(text),
          _throwsFormatNamingLine(line),
        );
      }

      test('a first line that is not a header', () {
        expectRejected('$good\n', 1);
      });

      test('a labels header, or a wrong format version', () {
        expectRejected('$_headerLine\n', 1);
        expectRejected(
          '${headerLine.replaceFirst('"formatVersion":1', '"formatVersion":2')}'
          '\n',
          1,
        );
      });

      test('a header missing its question hash or model', () {
        expectRejected(
          '${headerLine.replaceFirst(',"model":"claude-haiku-5-5"', '')}\n',
          1,
        );
        expectRejected(
          '${headerLine.replaceFirst('"questionHash":"q1",', '')}\n',
          1,
        );
      });

      test('a missing or extra key', () {
        expectRejected(
          '$headerLine\n{"code":"1","choice":"snacks"}\n',
          2,
        );
        expectRejected(
          '$headerLine\n'
          '{"code":"1","inputHash":"a","choice":"snacks","confidence":0.9}\n',
          2,
        );
      });

      test('an unknown choice', () {
        expectRejected(
          '$headerLine\n{"code":"1","inputHash":"a","choice":"frozen"}\n',
          2,
        );
      });

      test('a repeated code, on the line that repeats it', () {
        expectRejected('$headerLine\n$good\n$good\n', 3);
      });

      test('a line that is not JSON', () {
        expectRejected('$headerLine\nnot json\n', 2);
      });
    });
  });

  group('overrides CSV', () {
    const columns = 'code,name,brand,categories,aisle';

    test('writes the columns, LF rows, a trailing newline, sorted by code', () {
      final csv = encodeAisleOverrides([
        _override('2', name: 'Two', brand: '', categories: const []),
        _override(
          '1',
          name: 'One',
          brand: 'B',
          categories: const ['en:a', 'en:b'],
          aisle: FoodAisle.dairyEggs,
        ),
      ]);

      expect(
        csv,
        '$columns\n'
        '1,One,B,en:a en:b,dairyEggs\n'
        '2,Two,,,none\n',
      );
    });

    test('an empty file is its header row', () {
      expect(encodeAisleOverrides(const []), '$columns\n');
      expect(parseAisleOverrides('$columns\n'), isEmpty);
    });

    test('quotes commas, quotes and line breaks, and reads them back', () {
      const name = 'Oats, "rolled"\nwith\r\nbreaks';

      final csv = encodeAisleOverrides([_override('1', name: name)]);
      expect(
        csv,
        '$columns\n'
        '1,"Oats, ""rolled""\nwith\r\nbreaks",A brand,en:foods,none\n',
      );
      expect(parseAisleOverrides(csv).single.name, name);
    });

    test('prefixes formula cells with a quote and removes it on parse', () {
      for (final start in const ['=', '+', '-', '@', '\t', '\r']) {
        final name = '${start}1+1';
        final brand = '${start}brand';

        final csv =
            encodeAisleOverrides([_override('1', name: name, brand: brand)]);
        final cells = csv.split('\n')[1];
        expect(cells, contains("'$name"), reason: 'start ${start.codeUnits}');
        expect(cells, contains("'$brand"), reason: 'start ${start.codeUnits}');

        final row = parseAisleOverrides(csv).single;
        expect(row.name, name);
        expect(row.brand, brand);
      }
    });

    test('keeps a quote that protects nothing', () {
      const csv = "$columns\n1,'tis the season,'b,en:a,none\n";

      final row = parseAisleOverrides(csv).single;

      expect(row.name, "'tis the season");
      expect(row.brand, "'b");
    });

    test('reads an Aisle, none and unsure', () {
      final rows = parseAisleOverrides(
        '$columns\n'
        '1,n,b,en:a,snacks\n'
        '2,n,b,en:a,none\n'
        '3,n,b,en:a,unsure\n',
      );

      expect(rows[0].answer, AisleOverrideAnswer.aisle);
      expect(rows[0].aisle, FoodAisle.snacks);
      expect(rows[1].answer, AisleOverrideAnswer.none);
      expect(rows[1].aisle, isNull);
      expect(rows[2].answer, AisleOverrideAnswer.unsure);
      expect(rows[2].aisle, isNull);
      expect(encodeAisleOverrides(rows), contains('3,n,b,en:a,unsure\n'));
    });

    test('splits categories on single spaces, and empty is no tags', () {
      final rows = parseAisleOverrides(
        '$columns\n'
        '1,n,b,en:a en:b,none\n'
        '2,n,b,,none\n',
      );

      expect(rows[0].categories, ['en:a', 'en:b']);
      expect(rows[1].categories, isEmpty);
    });

    group('rejects', () {
      void expectRejected(String csv, int line) {
        expect(() => parseAisleOverrides(csv), _throwsFormatNamingLine(line));
      }

      test('an unknown column set', () {
        expectRejected('code,name\n', 1);
        expectRejected('$columns,sampled_as,set\n', 1);
        expectRejected('name,code,brand,categories,aisle\n', 1);
      });

      test('empty text, which has no header row', () {
        expectRejected('', 1);
      });

      test('an empty aisle', () {
        expectRejected('$columns\n1,n,b,en:a,\n', 2);
      });

      test('an unknown aisle', () {
        expectRejected('$columns\n1,n,b,en:a,frozen\n', 2);
        expectRejected('$columns\n1,n,b,en:a,other\n', 2);
      });

      test('the wrong number of cells', () {
        expectRejected('$columns\n1,n,b\n', 2);
      });

      test('a repeated code, on the line that repeats it', () {
        expectRejected(
          '$columns\n'
          '1,n,b,en:a,none\n'
          '1,n,b,en:a,snacks\n',
          3,
        );
      });

      test('a later row, counting line breaks inside quoted cells', () {
        expectRejected(
          '$columns\n'
          '1,"two\nlines",b,en:a,none\n'
          '2,n,b,en:a,frozen\n',
          4,
        );
      });
    });
  });

  group('tags export', () {
    test('finds the columns by name, in any order', () {
      final columns = parseAisleTagsHeader(
        'countries_tags\tx\tcode\tcategories_tags',
      );

      expect(columns.code, 2);
      expect(columns.categories, 3);
      expect(columns.countries, 0);
    });

    test('a missing column throws, naming it and line 1', () {
      for (final missing in const [
        'code',
        'categories_tags',
        'countries_tags',
      ]) {
        final header = const ['code', 'categories_tags', 'countries_tags']
            .where((name) => name != missing)
            .join('\t');
        expect(
          () => parseAisleTagsHeader(header),
          throwsA(
            isA<FormatException>()
                .having(
                    (error) => error.message, 'message', startsWith('line 1:'))
                .having((error) => error.message, 'message',
                    contains('"$missing"')),
          ),
        );
      }
    });

    const columns = AisleTagsColumns(code: 0, categories: 2, countries: 4);

    test('keeps en: tags in order, prefix kept, and drops the others', () {
      final row = parseAisleTagsRow(
        '0123\tname\ten:snacks,fr:chips,en:crisps,de:x\tother'
        '\ten:australia,fr:france,en:canada',
        columns,
      );

      expect(row!.code, '0123');
      expect(row.categories, ['en:snacks', 'en:crisps']);
      expect(row.countries, ['en:australia', 'en:canada']);
    });

    test('en:null, the export\'s empty value, gives no tags', () {
      final row = parseAisleTagsRow('1\tn\ten:null\to\ten:null', columns);

      expect(row!.categories, isEmpty);
      expect(row.countries, isEmpty);
    });

    test('an empty cell gives no tags', () {
      final row = parseAisleTagsRow('1\tn\t\to\t', columns);

      expect(row!.categories, isEmpty);
      expect(row.countries, isEmpty);
    });

    test('a row with too few cells gives null', () {
      expect(parseAisleTagsRow('1\tn\ten:snacks\to', columns), isNull);
      expect(parseAisleTagsRow('1', columns), isNull);
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

  group('isCurrentSecondOpinion', () {
    final header = AisleSecondOpinionsHeader(
      questionHash: aisleQuestionHash(),
      model: 'claude-haiku-5-5',
    );
    const AisleSecondOpinion opinion = (inputHash: 'a', aisle: null);

    test('a matching input hash and question is current', () {
      expect(isCurrentSecondOpinion(opinion, header, 'a'), isTrue);
    });

    test('a changed input hash is stale', () {
      expect(isCurrentSecondOpinion(opinion, header, 'b'), isFalse);
    });

    test('a changed question hash is stale', () {
      expect(
        isCurrentSecondOpinion(
          opinion,
          const AisleSecondOpinionsHeader(questionHash: 'q1', model: 'm'),
          'a',
        ),
        isFalse,
      );
    });

    test('no header or no second opinion is stale', () {
      expect(isCurrentSecondOpinion(opinion, null, 'a'), isFalse);
      expect(isCurrentSecondOpinion(null, header, 'a'), isFalse);
    });
  });

  group('isConfidentLabel', () {
    test('keeps an Aisle at the threshold and not one just below', () {
      expect(
          isConfidentLabel(_label(FoodAisle.snacks, confidence: 0.6)), isTrue);
      expect(isConfidentLabel(_label(FoodAisle.snacks, confidence: 0.599)),
          isFalse);
    });

    test('other at high confidence is not confident', () {
      expect(isConfidentLabel(_label(null, confidence: 0.99)), isFalse);
    });
  });

  group('resolveFoodAisle', () {
    final confident = _label(FoodAisle.snacks, confidence: 0.99);
    final low = _label(FoodAisle.snacks, confidence: 0.4);
    const AisleSecondOpinion saysSnacks =
        (inputHash: 'h', aisle: FoodAisle.snacks);
    const AisleSecondOpinion saysPantry =
        (inputHash: 'h', aisle: FoodAisle.pantry);
    const AisleSecondOpinion saysOther = (inputHash: 'h', aisle: null);

    test('an override Aisle beats a confident label', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          override: _override('1', aisle: FoodAisle.pantry),
        ),
        FoodAisle.pantry,
      );
    });

    test('an override none gives no Aisle even with a confident label', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          currentSecondOpinion: saysSnacks,
          override: _override('1'),
        ),
        isNull,
      );
    });

    test('unsure falls through to the label', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          override: _override('1', answer: AisleOverrideAnswer.unsure),
        ),
        FoodAisle.snacks,
      );
    });

    test('unsure falls through to agreement too', () {
      expect(
        resolveFoodAisle(
          currentLabel: low,
          currentSecondOpinion: saysSnacks,
          override: _override('1', answer: AisleOverrideAnswer.unsure),
        ),
        FoodAisle.snacks,
      );
    });

    test('a confident label beats a differing second opinion', () {
      expect(
        resolveFoodAisle(
          currentLabel: confident,
          currentSecondOpinion: saysPantry,
        ),
        FoodAisle.snacks,
      );
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

    test('a low label with an equal second opinion gives that Aisle', () {
      expect(
        resolveFoodAisle(currentLabel: low, currentSecondOpinion: saysSnacks),
        FoodAisle.snacks,
      );
    });

    test('a low label with a different second opinion gives no Aisle', () {
      expect(
        resolveFoodAisle(currentLabel: low, currentSecondOpinion: saysPantry),
        isNull,
      );
      expect(
        resolveFoodAisle(currentLabel: low, currentSecondOpinion: saysOther),
        isNull,
      );
    });

    test('a low label with no second opinion gives no Aisle', () {
      expect(resolveFoodAisle(currentLabel: low), isNull);
    });

    test('other with an Aisle second opinion gives no Aisle', () {
      expect(
        resolveFoodAisle(
          currentLabel: _label(null, confidence: 0.99),
          currentSecondOpinion: saysSnacks,
        ),
        isNull,
      );
    });

    test('both other gives no Aisle', () {
      expect(
        resolveFoodAisle(
          currentLabel: _label(null, confidence: 0.3),
          currentSecondOpinion: saysOther,
        ),
        isNull,
      );
    });

    test('no current label gives no Aisle, whatever the second opinion', () {
      expect(resolveFoodAisle(currentLabel: null), isNull);
      expect(
        resolveFoodAisle(currentLabel: null, currentSecondOpinion: saysSnacks),
        isNull,
      );
    });
  });

  group('resolveAisleBundle', () {
    test('gives one product per input line, in input order', () {
      final bundle = resolveAisleBundle(
        input: [_line('2', scans: 5), _line('1', scans: 9), _line('3')],
        labels: {
          '1': _label(FoodAisle.snacks),
          '2': _label(FoodAisle.drinks),
          '3': _label(FoodAisle.pantry, confidence: 0.3),
        },
        secondOpinions: const {'3': (inputHash: 'h', aisle: FoodAisle.pantry)},
        overrides: const [],
      );

      expect(bundle, [
        (code: '2', scans: 5, aisle: FoodAisle.drinks),
        (code: '1', scans: 9, aisle: FoodAisle.snacks),
        (code: '3', scans: 1, aisle: FoodAisle.pantry),
      ]);
    });

    test('a code with no label gets only the override step', () {
      final bundle = resolveAisleBundle(
        input: [_line('1'), _line('2')],
        labels: const {},
        secondOpinions: const {
          '1': (inputHash: 'h', aisle: FoodAisle.snacks),
          '2': (inputHash: 'h', aisle: FoodAisle.snacks),
        },
        overrides: [_override('1', aisle: FoodAisle.pantry)],
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

  group('secondOpinionsToAsk', () {
    test('asks only about labels that are not confident, other included', () {
      final input = [_line('1'), _line('2'), _line('3'), _line('4')];
      final labels = _currentLabels({
        '1': _label(FoodAisle.snacks, confidence: 0.9),
        '2': _label(FoodAisle.snacks, confidence: 0.4),
        '3': _label(null, confidence: 0.99),
        '4': _label(FoodAisle.snacks, confidence: 0.6),
      });

      final asked = secondOpinionsToAsk(input, labels, _noOpinions);

      expect(asked.map((line) => line.code), ['2', '3']);
    });

    test('a current second opinion is not asked again; a stale one is', () {
      final input = [_line('1'), _line('2'), _line('3', hash: 'new')];
      final labels = _currentLabels({
        '1': _label(FoodAisle.snacks, confidence: 0.4),
        '2': _label(FoodAisle.snacks, confidence: 0.4),
        '3': _label(FoodAisle.snacks, confidence: 0.4, hash: 'new'),
      });
      final opinions = _currentOpinions({
        '1': (inputHash: 'h', aisle: FoodAisle.snacks),
        '3': (inputHash: 'old', aisle: FoodAisle.snacks),
      });

      final asked = secondOpinionsToAsk(input, labels, opinions);

      expect(asked.map((line) => line.code), ['2', '3']);
    });

    test('second opinions under another question are all asked again', () {
      final input = [_line('1')];
      final labels = _currentLabels({
        '1': _label(FoodAisle.snacks, confidence: 0.4),
      });
      const opinions = AisleSecondOpinions(
        header: AisleSecondOpinionsHeader(questionHash: 'q1', model: 'm'),
        byCode: {'1': (inputHash: 'h', aisle: FoodAisle.snacks)},
      );

      expect(secondOpinionsToAsk(input, labels, opinions), hasLength(1));
    });

    test('a product with no current label is not asked about yet', () {
      final input = [_line('1'), _line('2')];
      final labels = _currentLabels({
        '2': _label(FoodAisle.snacks, confidence: 0.4, hash: 'old'),
      });

      expect(secondOpinionsToAsk(input, labels, _noOpinions), isEmpty);
    });
  });

  group('encodeSecondOpinionInput', () {
    final line = AisleInputLine(
      code: '0818290014313',
      name: 'Greek Yogurt Plain Nonfat',
      brand: 'Chobani',
      categories: const [
        'en:dairies',
        'en:fermented-foods',
        'en:fermented-milk-products',
        'en:yogurts',
        'en:greek-style-yogurts',
      ],
      scans: 412,
      inputHash: '352594eedc0b9cad',
    );

    test('the first line holds the instructions and criteria Clef is asked',
        () {
      final lines = encodeSecondOpinionInput([line]).split('\n');
      final question = jsonDecode(lines.first) as Map<String, Object?>;
      final clef = (aisleModelRequest(
          model: 'clef:latest',
          state: const {})['questions']! as Map)['aisle'] as Map;

      expect(question.keys, ['instructions', 'criteria', 'answer']);
      expect(question['instructions'], clef['instructions']);
      expect(jsonEncode(question['criteria']), jsonEncode(clef['criteria']));
      expect(
        question['answer'],
        'Reply with exactly one id from criteria, for each product.',
      );
    });

    test('a product line holds the code and the same state as Clef\'s', () {
      final text = encodeSecondOpinionInput([line]);
      final lines = text.split('\n');

      expect(lines, hasLength(3));
      expect(lines.last, isEmpty, reason: 'ends with a newline');
      expect(
        lines[1],
        '{"code":"0818290014313","state":${jsonEncode(aisleModelState(
          name: line.name,
          brand: line.brand,
          categories: line.categories,
        ))}}',
      );
    });

    test('no line holds Clef\'s answer', () {
      final text = encodeSecondOpinionInput([line]);

      expect(text, isNot(contains('confidence')));
      expect(text, isNot(contains('"choice"')));
      expect(text, isNot(contains('inputHash')));
    });

    test('with nothing to ask, it is the question line alone', () {
      expect(encodeSecondOpinionInput(const []).split('\n'), hasLength(2));
    });
  });

  group('parseSecondOpinionAnswers', () {
    test('reads code and choice in any order, skipping blank lines', () {
      final answers = parseSecondOpinionAnswers(
        '{"code":"2","choice":"other"}\n'
        '\n'
        '{"choice":"snacks","code":"1"}\n',
        asked: {'1', '2', '3'},
      );

      expect(answers, {'2': null, '1': FoodAisle.snacks});
    });

    test('an empty file is no answers', () {
      expect(parseSecondOpinionAnswers('', asked: {'1'}), isEmpty);
    });

    group('rejects, naming the line,', () {
      void expectRejected(String text, int line) {
        expect(
          () => parseSecondOpinionAnswers(text, asked: {'1', '2'}),
          _throwsFormatNamingLine(line),
        );
      }

      test('a code that was not asked', () {
        expectRejected(
          '{"code":"1","choice":"snacks"}\n{"code":"9","choice":"snacks"}\n',
          2,
        );
      });

      test('an unknown choice', () {
        expectRejected('{"code":"1","choice":"frozen"}\n', 1);
        expectRejected('{"code":"1","choice":"none"}\n', 1);
      });

      test('a missing or extra key', () {
        expectRejected('{"code":"1"}\n', 1);
        expectRejected('{"code":"1","choice":"snacks","confidence":0.9}\n', 1);
      });

      test('a repeated code', () {
        expectRejected(
          '{"code":"1","choice":"snacks"}\n{"code":"1","choice":"pantry"}\n',
          2,
        );
      });

      test('a line that is not a JSON object', () {
        expectRejected('["1","snacks"]\n', 1);
        expectRejected('not json\n', 1);
      });
    });
  });

  group('mergeSecondOpinions', () {
    const header = AisleSecondOpinionsHeader(
      questionHash: 'current',
      model: 'claude-haiku-5-5',
    );

    test('adds the answers, with each product\'s input hash, under header', () {
      final merged = mergeSecondOpinions(
        input: [_line('1', hash: 'a'), _line('2', hash: 'b')],
        labels: _currentLabels({
          '1': _label(FoodAisle.snacks, confidence: 0.4, hash: 'a'),
          '2': _label(null, confidence: 0.9, hash: 'b'),
        }),
        existing: _noOpinions,
        answers: {'1': FoodAisle.snacks, '2': null},
        header: header,
      );

      expect(merged.header, same(header));
      expect(merged.byCode, {
        '1': (inputHash: 'a', aisle: FoodAisle.snacks),
        '2': (inputHash: 'b', aisle: null),
      });
    });

    test('keeps current lines from the same model, an answer winning', () {
      final merged = mergeSecondOpinions(
        input: [_line('1'), _line('2'), _line('3')],
        labels: _currentLabels({
          '1': _label(FoodAisle.snacks, confidence: 0.4),
          '2': _label(FoodAisle.snacks, confidence: 0.4),
          '3': _label(FoodAisle.snacks, confidence: 0.4),
        }),
        existing: _currentOpinions({
          '1': (inputHash: 'h', aisle: FoodAisle.pantry),
          '2': (inputHash: 'h', aisle: FoodAisle.pantry),
          '3': (inputHash: 'stale', aisle: FoodAisle.pantry),
        }),
        answers: {'2': FoodAisle.snacks},
        header: header,
      );

      expect(merged.byCode, {
        '1': (inputHash: 'h', aisle: FoodAisle.pantry),
        '2': (inputHash: 'h', aisle: FoodAisle.snacks),
      });
    });

    test('drops the lines of another model', () {
      final merged = mergeSecondOpinions(
        input: [_line('1'), _line('2')],
        labels: _currentLabels({
          '1': _label(FoodAisle.snacks, confidence: 0.4),
          '2': _label(FoodAisle.snacks, confidence: 0.4),
        }),
        existing: _currentOpinions(
          {'1': (inputHash: 'h', aisle: FoodAisle.pantry)},
          model: 'another-model',
        ),
        answers: {'2': FoodAisle.snacks},
        header: header,
      );

      expect(merged.byCode.keys, ['2']);
    });

    test('drops codes whose label became confident or that left the input', () {
      final merged = mergeSecondOpinions(
        input: [_line('1'), _line('2')],
        labels: _currentLabels({
          '1': _label(FoodAisle.snacks, confidence: 0.95),
          '2': _label(FoodAisle.snacks, confidence: 0.4),
        }),
        existing: _currentOpinions({
          '1': (inputHash: 'h', aisle: FoodAisle.snacks),
          '2': (inputHash: 'h', aisle: FoodAisle.snacks),
          '9': (inputHash: 'h', aisle: FoodAisle.snacks),
        }),
        answers: const {},
        header: header,
      );

      expect(merged.byCode.keys, ['2']);
    });
  });

  group('selectAisleEdgeCases', () {
    List<AisleEdgeCase> select(
      List<AisleInputLine> input,
      Map<String, AisleLabel> labels,
      Map<String, AisleSecondOpinion> opinions, {
      List<AisleOverrideRow> overrides = const [],
    }) {
      return selectAisleEdgeCases(
        input: input,
        labels: _currentLabels(labels),
        opinions: _currentOpinions(opinions),
        overrides: overrides,
      );
    }

    test('different choices are edge cases; agreement and both other not', () {
      final cases = select(
        [_line('1'), _line('2'), _line('3'), _line('4'), _line('5')],
        {
          '1': _label(FoodAisle.snacks, confidence: 0.4),
          '2': _label(FoodAisle.snacks, confidence: 0.4),
          '3': _label(null, confidence: 0.4),
          '4': _label(null, confidence: 0.9),
          '5': _label(FoodAisle.snacks, confidence: 0.4),
        },
        {
          '1': (inputHash: 'h', aisle: FoodAisle.pantry),
          '2': (inputHash: 'h', aisle: FoodAisle.snacks),
          '3': (inputHash: 'h', aisle: null),
          '4': (inputHash: 'h', aisle: FoodAisle.drinks),
          '5': (inputHash: 'h', aisle: null),
        },
      );

      expect(cases.map((edgeCase) => edgeCase.line.code), ['1', '4', '5']);
      expect(cases.first.label.aisle, FoodAisle.snacks);
      expect(cases.first.secondOpinion.aisle, FoodAisle.pantry);
    });

    test('a confident label is never an edge case', () {
      final cases = select(
        [_line('1')],
        {'1': _label(FoodAisle.snacks, confidence: 0.9)},
        {'1': (inputHash: 'h', aisle: FoodAisle.pantry)},
      );

      expect(cases, isEmpty);
    });

    test('a product with a stale second opinion is not an edge case yet', () {
      final cases = select(
        [_line('1')],
        {'1': _label(FoodAisle.snacks, confidence: 0.4)},
        {'1': (inputHash: 'old', aisle: FoodAisle.pantry)},
      );

      expect(cases, isEmpty);
    });

    test('a product with an override row is left out, unsure included', () {
      final cases = select(
        [_line('1'), _line('2'), _line('3'), _line('4')],
        {
          for (final code in ['1', '2', '3', '4'])
            code: _label(FoodAisle.snacks, confidence: 0.4),
        },
        {
          for (final code in ['1', '2', '3', '4'])
            code: (inputHash: 'h', aisle: FoodAisle.pantry),
        },
        overrides: [
          _override('1', aisle: FoodAisle.snacks),
          _override('2'),
          _override('3', answer: AisleOverrideAnswer.unsure),
        ],
      );

      expect(cases.map((edgeCase) => edgeCase.line.code), ['4']);
    });

    test('orders by scans descending, then code ascending', () {
      final cases = select(
        [
          _line('c', scans: 5),
          _line('a', scans: 9),
          _line('d', scans: 5),
          _line('b', scans: 1),
        ],
        {
          for (final code in ['a', 'b', 'c', 'd'])
            code: _label(FoodAisle.snacks, confidence: 0.4),
        },
        {
          for (final code in ['a', 'b', 'c', 'd'])
            code: (inputHash: 'h', aisle: FoodAisle.pantry),
        },
      );

      expect(cases.map((edgeCase) => edgeCase.line.code), ['a', 'c', 'd', 'b']);
    });

    test('keeps at most aisleReviewLimit, the most scanned', () {
      expect(aisleReviewLimit, 50);
      final codes = [for (var i = 0; i < 60; i += 1) _code(i)];
      final cases = select(
        [for (final code in codes) _line(code, scans: int.parse(code))],
        {
          for (final code in codes)
            code: _label(FoodAisle.snacks, confidence: 0.4),
        },
        {
          for (final code in codes)
            code: (inputHash: 'h', aisle: FoodAisle.pantry),
        },
      );

      expect(cases, hasLength(50));
      expect(cases.first.line.code, _code(59));
      expect(cases.last.line.code, _code(10));
    });
  });

  group('aisleReviewPage', () {
    AisleEdgeCase edgeCase(
      String code, {
      String name = 'A product',
      String? brand = 'A brand',
      List<String> categories = const ['en:snacks', 'en:crisps'],
    }) {
      return AisleEdgeCase(
        line: AisleInputLine(
          code: code,
          name: name,
          brand: brand,
          categories: categories,
          scans: 3,
          inputHash: 'h',
        ),
        label: _label(FoodAisle.snacks, confidence: 0.452),
        secondOpinion: (inputHash: 'h', aisle: FoodAisle.sweetsDesserts),
      );
    }

    test('shows each product\'s name, brand, tags, both answers, confidence',
        () {
      final page = aisleReviewPage(
        [edgeCase('1', name: 'Salted crisps'), edgeCase('2', name: 'Oat bar')],
        postPath: '/token',
      );

      expect(page, startsWith('<!doctype html>'));
      expect(page, contains('Salted crisps'));
      expect(page, contains('Oat bar'));
      expect(page, contains('A brand'));
      expect(page, contains('en:crisps'));
      expect(page, contains('Snacks (snacks)'));
      expect(page, contains('Sweets &amp; desserts (sweetsDesserts)'));
      expect(page, contains('0.452'));
      expect(page, contains('data-post-path="/token"'));
    });

    test('has a button per Aisle, by its UI label, then none and unsure', () {
      final page = aisleReviewPage([edgeCase('1')], postPath: '/token');

      var position = 0;
      for (final id in [
        for (final aisle in FoodAisle.values) aisle.name,
        'none',
        'unsure',
      ]) {
        final found = page.indexOf('data-aisle="$id"', position);
        expect(found, greaterThan(position), reason: id);
        position = found;
      }
      for (final aisle in FoodAisle.values) {
        expect(
          page,
          contains('>${aisle.label.replaceAll('&', '&amp;')}</button>'),
        );
      }
    });

    test('holds the guide', () {
      final page = aisleReviewPage([edgeCase('1')], postPath: '/token');

      for (final principle in aislePrinciples) {
        expect(page, contains(principle.split('(').first.trim()));
      }
      expect(page, contains('<details>'));
    });

    test('loads nothing from elsewhere: no http:// or https:// URL', () {
      final page = aisleReviewPage(
        [edgeCase('1'), edgeCase('2', brand: null, categories: const [])],
        postPath: '/token',
      );

      expect(page, isNot(contains('http://')));
      expect(page, isNot(contains('https://')));
      expect(page, isNot(contains(' src=')));
      expect(page, isNot(contains('<link')));
    });

    test('escapes every product field as HTML text', () {
      const hostile = '<script>alert("x")</script>';
      final page = aisleReviewPage(
        [
          edgeCase(
            '"><img onerror=x>',
            name: hostile,
            brand: "O'Brien & <b>Sons</b>",
            categories: const ['en:<i>tag</i>'],
          ),
        ],
        postPath: '/token',
      );

      expect(page, isNot(contains(hostile)));
      expect(
        page,
        contains('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'),
      );
      expect(page, contains('O&#39;Brien &amp; &lt;b&gt;Sons&lt;/b&gt;'));
      expect(page, contains('en:&lt;i&gt;tag&lt;/i&gt;'));
      expect(page, isNot(contains('<img')));
      expect(page, contains('&quot;&gt;&lt;img onerror=x&gt;'));
      // The page's own script is the only one.
      expect('<script>'.allMatches(page), hasLength(1));
    });
  });

  group('aisleLabelFromResponse', () {
    AisleLabel? label(Object? response) {
      return aisleLabelFromResponse(response, inputHash: 'hash');
    }

    test('reads the choice and confidence, ignoring the rest', () {
      final response = jsonDecode(
        '{"answers":{"aisle":{"choice":"sweetsDesserts","confidence":0.9136,'
        '"probabilities":{"alcohol":0.0019,"sweetsDesserts":0.9194}}}}',
      );

      expect(label(response), (
        inputHash: 'hash',
        aisle: FoodAisle.sweetsDesserts,
        confidence: 0.914,
      ));
    });

    test('other is a usable answer with no Aisle', () {
      expect(
        label({
          'answers': {
            'aisle': {'choice': 'other', 'confidence': 1},
          },
        }),
        (inputHash: 'hash', aisle: null, confidence: 1.0),
      );
    });

    test('rounds as the file does, so the threshold reads the same value', () {
      final made = label({
        'answers': {
          'aisle': {'choice': 'snacks', 'confidence': 0.5996},
        },
      })!;

      expect(made.confidence, 0.6);
      expect(resolveFoodAisle(currentLabel: made), FoodAisle.snacks);
    });

    test('no usable answer gives null', () {
      for (final response in <Object?>[
        null,
        'text',
        <String, Object?>{},
        {'answers': 'text'},
        {
          'answers': {'aisle': 'snacks'},
        },
        {
          'answers': {
            'aisle': {'choice': 'snacks'},
          },
        },
        {
          'answers': {
            'aisle': {'confidence': 0.9},
          },
        },
        {
          'answers': {
            'aisle': {'choice': 'frozen', 'confidence': 0.9},
          },
        },
        {
          'answers': {
            'aisle': {'choice': 3, 'confidence': 0.9},
          },
        },
        {
          'answers': {
            'aisle': {'choice': 'snacks', 'confidence': '0.9'},
          },
        },
        {
          'answers': {
            'aisle': {'choice': 'snacks', 'confidence': 1.2},
          },
        },
        {
          'answers': {
            'aisle': {'choice': 'snacks', 'confidence': -0.1},
          },
        },
      ]) {
        expect(label(response), isNull, reason: '$response');
      }
    });
  });

  group('matchOllamaModel', () {
    const tags = {
      'models': [
        {'name': 'llama3:8b', 'digest': 'a'},
        {'name': 'clef:latest', 'digest': 'b'},
        {'name': 'clef:small', 'digest': 'c'},
      ],
    };

    test('a name with no tag matches its :latest', () {
      expect(
          matchOllamaModel(tags, 'clef'), (name: 'clef:latest', digest: 'b'));
    });

    test('a name with a tag matches only that tag', () {
      expect(matchOllamaModel(tags, 'clef:small'), (
        name: 'clef:small',
        digest: 'c',
      ));
      expect(matchOllamaModel(tags, 'clef:large'), isNull);
      expect(matchOllamaModel(tags, 'llama3'), isNull);
    });

    test('a name matches itself when it has no tag in the list', () {
      expect(
        matchOllamaModel({
          'models': [
            {'name': 'clef', 'digest': 'd'},
          ],
        }, 'clef'),
        (name: 'clef', digest: 'd'),
      );
    });

    test('a response of another shape matches nothing', () {
      for (final response in <Object?>[
        null,
        'text',
        <String, Object?>{},
        {'models': 'text'},
        {
          'models': ['clef:latest'],
        },
        {
          'models': [
            {'name': 'clef:latest'},
          ],
        },
      ]) {
        expect(matchOllamaModel(response, 'clef'), isNull, reason: '$response');
      }
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
