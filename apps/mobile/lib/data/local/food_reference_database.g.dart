// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'food_reference_database.dart';

// ignore_for_file: type=lint
class $ReferenceMetaTable extends ReferenceMeta
    with TableInfo<$ReferenceMetaTable, ReferenceMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReferenceMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reference_meta';
  @override
  VerificationContext validateIntegrity(Insertable<ReferenceMetaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ReferenceMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReferenceMetaRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $ReferenceMetaTable createAlias(String alias) {
    return $ReferenceMetaTable(attachedDatabase, alias);
  }
}

class ReferenceMetaRow extends DataClass
    implements Insertable<ReferenceMetaRow> {
  final String key;
  final String value;
  const ReferenceMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  ReferenceMetaCompanion toCompanion(bool nullToAbsent) {
    return ReferenceMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory ReferenceMetaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReferenceMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  ReferenceMetaRow copyWith({String? key, String? value}) => ReferenceMetaRow(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  ReferenceMetaRow copyWithCompanion(ReferenceMetaCompanion data) {
    return ReferenceMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReferenceMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class ReferenceMetaCompanion extends UpdateCompanion<ReferenceMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const ReferenceMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReferenceMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<ReferenceMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReferenceMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return ReferenceMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OpenFoodFactsProductsTable extends OpenFoodFactsProducts
    with TableInfo<$OpenFoodFactsProductsTable, OpenFoodFactsProductRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpenFoodFactsProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
      'brand', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isLiquidMeta =
      const VerificationMeta('isLiquid');
  @override
  late final GeneratedColumn<bool> isLiquid = GeneratedColumn<bool>(
      'is_liquid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_liquid" IN (0, 1))'));
  static const VerificationMeta _servingLabelMeta =
      const VerificationMeta('servingLabel');
  @override
  late final GeneratedColumn<String> servingLabel = GeneratedColumn<String>(
      'serving_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _servingSizeMeta =
      const VerificationMeta('servingSize');
  @override
  late final GeneratedColumn<double> servingSize = GeneratedColumn<double>(
      'serving_size', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _packageSizeMeta =
      const VerificationMeta('packageSize');
  @override
  late final GeneratedColumn<double> packageSize = GeneratedColumn<double>(
      'package_size', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _nutrientsJsonMeta =
      const VerificationMeta('nutrientsJson');
  @override
  late final GeneratedColumn<String> nutrientsJson = GeneratedColumn<String>(
      'nutrients_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _modifiedAtMeta =
      const VerificationMeta('modifiedAt');
  @override
  late final GeneratedColumn<int> modifiedAt = GeneratedColumn<int>(
      'modified_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _scansMeta = const VerificationMeta('scans');
  @override
  late final GeneratedColumn<int> scans = GeneratedColumn<int>(
      'scans', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        code,
        name,
        brand,
        isLiquid,
        servingLabel,
        servingSize,
        packageSize,
        nutrientsJson,
        modifiedAt,
        scans,
        origin
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'open_food_facts_products';
  @override
  VerificationContext validateIntegrity(
      Insertable<OpenFoodFactsProductRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
          _brandMeta, brand.isAcceptableOrUnknown(data['brand']!, _brandMeta));
    }
    if (data.containsKey('is_liquid')) {
      context.handle(_isLiquidMeta,
          isLiquid.isAcceptableOrUnknown(data['is_liquid']!, _isLiquidMeta));
    } else if (isInserting) {
      context.missing(_isLiquidMeta);
    }
    if (data.containsKey('serving_label')) {
      context.handle(
          _servingLabelMeta,
          servingLabel.isAcceptableOrUnknown(
              data['serving_label']!, _servingLabelMeta));
    }
    if (data.containsKey('serving_size')) {
      context.handle(
          _servingSizeMeta,
          servingSize.isAcceptableOrUnknown(
              data['serving_size']!, _servingSizeMeta));
    }
    if (data.containsKey('package_size')) {
      context.handle(
          _packageSizeMeta,
          packageSize.isAcceptableOrUnknown(
              data['package_size']!, _packageSizeMeta));
    }
    if (data.containsKey('nutrients_json')) {
      context.handle(
          _nutrientsJsonMeta,
          nutrientsJson.isAcceptableOrUnknown(
              data['nutrients_json']!, _nutrientsJsonMeta));
    } else if (isInserting) {
      context.missing(_nutrientsJsonMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
          _modifiedAtMeta,
          modifiedAt.isAcceptableOrUnknown(
              data['modified_at']!, _modifiedAtMeta));
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('scans')) {
      context.handle(
          _scansMeta, scans.isAcceptableOrUnknown(data['scans']!, _scansMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OpenFoodFactsProductRow map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpenFoodFactsProductRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      brand: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}brand']),
      isLiquid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_liquid'])!,
      servingLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}serving_label']),
      servingSize: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}serving_size']),
      packageSize: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}package_size']),
      nutrientsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}nutrients_json'])!,
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}modified_at'])!,
      scans: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}scans']),
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
    );
  }

  @override
  $OpenFoodFactsProductsTable createAlias(String alias) {
    return $OpenFoodFactsProductsTable(attachedDatabase, alias);
  }
}

class OpenFoodFactsProductRow extends DataClass
    implements Insertable<OpenFoodFactsProductRow> {
  /// The FTS5 row id. The database is never vacuumed, so ids stay stable.
  final int id;
  final String code;
  final String name;
  final String? brand;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  /// The compact form: Nutrient storage key → entered text, as in a bundle
  /// product line.
  final String nutrientsJson;

  /// Unix seconds.
  final int modifiedAt;
  final int? scans;
  final String origin;
  const OpenFoodFactsProductRow(
      {required this.id,
      required this.code,
      required this.name,
      this.brand,
      required this.isLiquid,
      this.servingLabel,
      this.servingSize,
      this.packageSize,
      required this.nutrientsJson,
      required this.modifiedAt,
      this.scans,
      required this.origin});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    map['is_liquid'] = Variable<bool>(isLiquid);
    if (!nullToAbsent || servingLabel != null) {
      map['serving_label'] = Variable<String>(servingLabel);
    }
    if (!nullToAbsent || servingSize != null) {
      map['serving_size'] = Variable<double>(servingSize);
    }
    if (!nullToAbsent || packageSize != null) {
      map['package_size'] = Variable<double>(packageSize);
    }
    map['nutrients_json'] = Variable<String>(nutrientsJson);
    map['modified_at'] = Variable<int>(modifiedAt);
    if (!nullToAbsent || scans != null) {
      map['scans'] = Variable<int>(scans);
    }
    map['origin'] = Variable<String>(origin);
    return map;
  }

  OpenFoodFactsProductsCompanion toCompanion(bool nullToAbsent) {
    return OpenFoodFactsProductsCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      brand:
          brand == null && nullToAbsent ? const Value.absent() : Value(brand),
      isLiquid: Value(isLiquid),
      servingLabel: servingLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(servingLabel),
      servingSize: servingSize == null && nullToAbsent
          ? const Value.absent()
          : Value(servingSize),
      packageSize: packageSize == null && nullToAbsent
          ? const Value.absent()
          : Value(packageSize),
      nutrientsJson: Value(nutrientsJson),
      modifiedAt: Value(modifiedAt),
      scans:
          scans == null && nullToAbsent ? const Value.absent() : Value(scans),
      origin: Value(origin),
    );
  }

  factory OpenFoodFactsProductRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpenFoodFactsProductRow(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String?>(json['brand']),
      isLiquid: serializer.fromJson<bool>(json['isLiquid']),
      servingLabel: serializer.fromJson<String?>(json['servingLabel']),
      servingSize: serializer.fromJson<double?>(json['servingSize']),
      packageSize: serializer.fromJson<double?>(json['packageSize']),
      nutrientsJson: serializer.fromJson<String>(json['nutrientsJson']),
      modifiedAt: serializer.fromJson<int>(json['modifiedAt']),
      scans: serializer.fromJson<int?>(json['scans']),
      origin: serializer.fromJson<String>(json['origin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String?>(brand),
      'isLiquid': serializer.toJson<bool>(isLiquid),
      'servingLabel': serializer.toJson<String?>(servingLabel),
      'servingSize': serializer.toJson<double?>(servingSize),
      'packageSize': serializer.toJson<double?>(packageSize),
      'nutrientsJson': serializer.toJson<String>(nutrientsJson),
      'modifiedAt': serializer.toJson<int>(modifiedAt),
      'scans': serializer.toJson<int?>(scans),
      'origin': serializer.toJson<String>(origin),
    };
  }

  OpenFoodFactsProductRow copyWith(
          {int? id,
          String? code,
          String? name,
          Value<String?> brand = const Value.absent(),
          bool? isLiquid,
          Value<String?> servingLabel = const Value.absent(),
          Value<double?> servingSize = const Value.absent(),
          Value<double?> packageSize = const Value.absent(),
          String? nutrientsJson,
          int? modifiedAt,
          Value<int?> scans = const Value.absent(),
          String? origin}) =>
      OpenFoodFactsProductRow(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        brand: brand.present ? brand.value : this.brand,
        isLiquid: isLiquid ?? this.isLiquid,
        servingLabel:
            servingLabel.present ? servingLabel.value : this.servingLabel,
        servingSize: servingSize.present ? servingSize.value : this.servingSize,
        packageSize: packageSize.present ? packageSize.value : this.packageSize,
        nutrientsJson: nutrientsJson ?? this.nutrientsJson,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        scans: scans.present ? scans.value : this.scans,
        origin: origin ?? this.origin,
      );
  OpenFoodFactsProductRow copyWithCompanion(
      OpenFoodFactsProductsCompanion data) {
    return OpenFoodFactsProductRow(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      isLiquid: data.isLiquid.present ? data.isLiquid.value : this.isLiquid,
      servingLabel: data.servingLabel.present
          ? data.servingLabel.value
          : this.servingLabel,
      servingSize:
          data.servingSize.present ? data.servingSize.value : this.servingSize,
      packageSize:
          data.packageSize.present ? data.packageSize.value : this.packageSize,
      nutrientsJson: data.nutrientsJson.present
          ? data.nutrientsJson.value
          : this.nutrientsJson,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      scans: data.scans.present ? data.scans.value : this.scans,
      origin: data.origin.present ? data.origin.value : this.origin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpenFoodFactsProductRow(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('isLiquid: $isLiquid, ')
          ..write('servingLabel: $servingLabel, ')
          ..write('servingSize: $servingSize, ')
          ..write('packageSize: $packageSize, ')
          ..write('nutrientsJson: $nutrientsJson, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('scans: $scans, ')
          ..write('origin: $origin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, code, name, brand, isLiquid, servingLabel,
      servingSize, packageSize, nutrientsJson, modifiedAt, scans, origin);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpenFoodFactsProductRow &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.isLiquid == this.isLiquid &&
          other.servingLabel == this.servingLabel &&
          other.servingSize == this.servingSize &&
          other.packageSize == this.packageSize &&
          other.nutrientsJson == this.nutrientsJson &&
          other.modifiedAt == this.modifiedAt &&
          other.scans == this.scans &&
          other.origin == this.origin);
}

class OpenFoodFactsProductsCompanion
    extends UpdateCompanion<OpenFoodFactsProductRow> {
  final Value<int> id;
  final Value<String> code;
  final Value<String> name;
  final Value<String?> brand;
  final Value<bool> isLiquid;
  final Value<String?> servingLabel;
  final Value<double?> servingSize;
  final Value<double?> packageSize;
  final Value<String> nutrientsJson;
  final Value<int> modifiedAt;
  final Value<int?> scans;
  final Value<String> origin;
  const OpenFoodFactsProductsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.isLiquid = const Value.absent(),
    this.servingLabel = const Value.absent(),
    this.servingSize = const Value.absent(),
    this.packageSize = const Value.absent(),
    this.nutrientsJson = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.scans = const Value.absent(),
    this.origin = const Value.absent(),
  });
  OpenFoodFactsProductsCompanion.insert({
    this.id = const Value.absent(),
    required String code,
    required String name,
    this.brand = const Value.absent(),
    required bool isLiquid,
    this.servingLabel = const Value.absent(),
    this.servingSize = const Value.absent(),
    this.packageSize = const Value.absent(),
    required String nutrientsJson,
    required int modifiedAt,
    this.scans = const Value.absent(),
    required String origin,
  })  : code = Value(code),
        name = Value(name),
        isLiquid = Value(isLiquid),
        nutrientsJson = Value(nutrientsJson),
        modifiedAt = Value(modifiedAt),
        origin = Value(origin);
  static Insertable<OpenFoodFactsProductRow> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<bool>? isLiquid,
    Expression<String>? servingLabel,
    Expression<double>? servingSize,
    Expression<double>? packageSize,
    Expression<String>? nutrientsJson,
    Expression<int>? modifiedAt,
    Expression<int>? scans,
    Expression<String>? origin,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (isLiquid != null) 'is_liquid': isLiquid,
      if (servingLabel != null) 'serving_label': servingLabel,
      if (servingSize != null) 'serving_size': servingSize,
      if (packageSize != null) 'package_size': packageSize,
      if (nutrientsJson != null) 'nutrients_json': nutrientsJson,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (scans != null) 'scans': scans,
      if (origin != null) 'origin': origin,
    });
  }

  OpenFoodFactsProductsCompanion copyWith(
      {Value<int>? id,
      Value<String>? code,
      Value<String>? name,
      Value<String?>? brand,
      Value<bool>? isLiquid,
      Value<String?>? servingLabel,
      Value<double?>? servingSize,
      Value<double?>? packageSize,
      Value<String>? nutrientsJson,
      Value<int>? modifiedAt,
      Value<int?>? scans,
      Value<String>? origin}) {
    return OpenFoodFactsProductsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      isLiquid: isLiquid ?? this.isLiquid,
      servingLabel: servingLabel ?? this.servingLabel,
      servingSize: servingSize ?? this.servingSize,
      packageSize: packageSize ?? this.packageSize,
      nutrientsJson: nutrientsJson ?? this.nutrientsJson,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      scans: scans ?? this.scans,
      origin: origin ?? this.origin,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (isLiquid.present) {
      map['is_liquid'] = Variable<bool>(isLiquid.value);
    }
    if (servingLabel.present) {
      map['serving_label'] = Variable<String>(servingLabel.value);
    }
    if (servingSize.present) {
      map['serving_size'] = Variable<double>(servingSize.value);
    }
    if (packageSize.present) {
      map['package_size'] = Variable<double>(packageSize.value);
    }
    if (nutrientsJson.present) {
      map['nutrients_json'] = Variable<String>(nutrientsJson.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<int>(modifiedAt.value);
    }
    if (scans.present) {
      map['scans'] = Variable<int>(scans.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpenFoodFactsProductsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('isLiquid: $isLiquid, ')
          ..write('servingLabel: $servingLabel, ')
          ..write('servingSize: $servingSize, ')
          ..write('packageSize: $packageSize, ')
          ..write('nutrientsJson: $nutrientsJson, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('scans: $scans, ')
          ..write('origin: $origin')
          ..write(')'))
        .toString();
  }
}

abstract class _$FoodReferenceDatabase extends GeneratedDatabase {
  _$FoodReferenceDatabase(QueryExecutor e) : super(e);
  $FoodReferenceDatabaseManager get managers =>
      $FoodReferenceDatabaseManager(this);
  late final $ReferenceMetaTable referenceMeta = $ReferenceMetaTable(this);
  late final $OpenFoodFactsProductsTable openFoodFactsProducts =
      $OpenFoodFactsProductsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [referenceMeta, openFoodFactsProducts];
}

typedef $$ReferenceMetaTableCreateCompanionBuilder = ReferenceMetaCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$ReferenceMetaTableUpdateCompanionBuilder = ReferenceMetaCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$ReferenceMetaTableFilterComposer
    extends Composer<_$FoodReferenceDatabase, $ReferenceMetaTable> {
  $$ReferenceMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$ReferenceMetaTableOrderingComposer
    extends Composer<_$FoodReferenceDatabase, $ReferenceMetaTable> {
  $$ReferenceMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$ReferenceMetaTableAnnotationComposer
    extends Composer<_$FoodReferenceDatabase, $ReferenceMetaTable> {
  $$ReferenceMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$ReferenceMetaTableTableManager extends RootTableManager<
    _$FoodReferenceDatabase,
    $ReferenceMetaTable,
    ReferenceMetaRow,
    $$ReferenceMetaTableFilterComposer,
    $$ReferenceMetaTableOrderingComposer,
    $$ReferenceMetaTableAnnotationComposer,
    $$ReferenceMetaTableCreateCompanionBuilder,
    $$ReferenceMetaTableUpdateCompanionBuilder,
    (
      ReferenceMetaRow,
      BaseReferences<_$FoodReferenceDatabase, $ReferenceMetaTable,
          ReferenceMetaRow>
    ),
    ReferenceMetaRow,
    PrefetchHooks Function()> {
  $$ReferenceMetaTableTableManager(
      _$FoodReferenceDatabase db, $ReferenceMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReferenceMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReferenceMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReferenceMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ReferenceMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              ReferenceMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ReferenceMetaTableProcessedTableManager = ProcessedTableManager<
    _$FoodReferenceDatabase,
    $ReferenceMetaTable,
    ReferenceMetaRow,
    $$ReferenceMetaTableFilterComposer,
    $$ReferenceMetaTableOrderingComposer,
    $$ReferenceMetaTableAnnotationComposer,
    $$ReferenceMetaTableCreateCompanionBuilder,
    $$ReferenceMetaTableUpdateCompanionBuilder,
    (
      ReferenceMetaRow,
      BaseReferences<_$FoodReferenceDatabase, $ReferenceMetaTable,
          ReferenceMetaRow>
    ),
    ReferenceMetaRow,
    PrefetchHooks Function()>;
typedef $$OpenFoodFactsProductsTableCreateCompanionBuilder
    = OpenFoodFactsProductsCompanion Function({
  Value<int> id,
  required String code,
  required String name,
  Value<String?> brand,
  required bool isLiquid,
  Value<String?> servingLabel,
  Value<double?> servingSize,
  Value<double?> packageSize,
  required String nutrientsJson,
  required int modifiedAt,
  Value<int?> scans,
  required String origin,
});
typedef $$OpenFoodFactsProductsTableUpdateCompanionBuilder
    = OpenFoodFactsProductsCompanion Function({
  Value<int> id,
  Value<String> code,
  Value<String> name,
  Value<String?> brand,
  Value<bool> isLiquid,
  Value<String?> servingLabel,
  Value<double?> servingSize,
  Value<double?> packageSize,
  Value<String> nutrientsJson,
  Value<int> modifiedAt,
  Value<int?> scans,
  Value<String> origin,
});

class $$OpenFoodFactsProductsTableFilterComposer
    extends Composer<_$FoodReferenceDatabase, $OpenFoodFactsProductsTable> {
  $$OpenFoodFactsProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get brand => $composableBuilder(
      column: $table.brand, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isLiquid => $composableBuilder(
      column: $table.isLiquid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get servingLabel => $composableBuilder(
      column: $table.servingLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get servingSize => $composableBuilder(
      column: $table.servingSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get packageSize => $composableBuilder(
      column: $table.packageSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nutrientsJson => $composableBuilder(
      column: $table.nutrientsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get scans => $composableBuilder(
      column: $table.scans, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));
}

class $$OpenFoodFactsProductsTableOrderingComposer
    extends Composer<_$FoodReferenceDatabase, $OpenFoodFactsProductsTable> {
  $$OpenFoodFactsProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get brand => $composableBuilder(
      column: $table.brand, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isLiquid => $composableBuilder(
      column: $table.isLiquid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get servingLabel => $composableBuilder(
      column: $table.servingLabel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get servingSize => $composableBuilder(
      column: $table.servingSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get packageSize => $composableBuilder(
      column: $table.packageSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nutrientsJson => $composableBuilder(
      column: $table.nutrientsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get scans => $composableBuilder(
      column: $table.scans, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));
}

class $$OpenFoodFactsProductsTableAnnotationComposer
    extends Composer<_$FoodReferenceDatabase, $OpenFoodFactsProductsTable> {
  $$OpenFoodFactsProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<bool> get isLiquid =>
      $composableBuilder(column: $table.isLiquid, builder: (column) => column);

  GeneratedColumn<String> get servingLabel => $composableBuilder(
      column: $table.servingLabel, builder: (column) => column);

  GeneratedColumn<double> get servingSize => $composableBuilder(
      column: $table.servingSize, builder: (column) => column);

  GeneratedColumn<double> get packageSize => $composableBuilder(
      column: $table.packageSize, builder: (column) => column);

  GeneratedColumn<String> get nutrientsJson => $composableBuilder(
      column: $table.nutrientsJson, builder: (column) => column);

  GeneratedColumn<int> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<int> get scans =>
      $composableBuilder(column: $table.scans, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);
}

class $$OpenFoodFactsProductsTableTableManager extends RootTableManager<
    _$FoodReferenceDatabase,
    $OpenFoodFactsProductsTable,
    OpenFoodFactsProductRow,
    $$OpenFoodFactsProductsTableFilterComposer,
    $$OpenFoodFactsProductsTableOrderingComposer,
    $$OpenFoodFactsProductsTableAnnotationComposer,
    $$OpenFoodFactsProductsTableCreateCompanionBuilder,
    $$OpenFoodFactsProductsTableUpdateCompanionBuilder,
    (
      OpenFoodFactsProductRow,
      BaseReferences<_$FoodReferenceDatabase, $OpenFoodFactsProductsTable,
          OpenFoodFactsProductRow>
    ),
    OpenFoodFactsProductRow,
    PrefetchHooks Function()> {
  $$OpenFoodFactsProductsTableTableManager(
      _$FoodReferenceDatabase db, $OpenFoodFactsProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpenFoodFactsProductsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$OpenFoodFactsProductsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpenFoodFactsProductsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> code = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> brand = const Value.absent(),
            Value<bool> isLiquid = const Value.absent(),
            Value<String?> servingLabel = const Value.absent(),
            Value<double?> servingSize = const Value.absent(),
            Value<double?> packageSize = const Value.absent(),
            Value<String> nutrientsJson = const Value.absent(),
            Value<int> modifiedAt = const Value.absent(),
            Value<int?> scans = const Value.absent(),
            Value<String> origin = const Value.absent(),
          }) =>
              OpenFoodFactsProductsCompanion(
            id: id,
            code: code,
            name: name,
            brand: brand,
            isLiquid: isLiquid,
            servingLabel: servingLabel,
            servingSize: servingSize,
            packageSize: packageSize,
            nutrientsJson: nutrientsJson,
            modifiedAt: modifiedAt,
            scans: scans,
            origin: origin,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String code,
            required String name,
            Value<String?> brand = const Value.absent(),
            required bool isLiquid,
            Value<String?> servingLabel = const Value.absent(),
            Value<double?> servingSize = const Value.absent(),
            Value<double?> packageSize = const Value.absent(),
            required String nutrientsJson,
            required int modifiedAt,
            Value<int?> scans = const Value.absent(),
            required String origin,
          }) =>
              OpenFoodFactsProductsCompanion.insert(
            id: id,
            code: code,
            name: name,
            brand: brand,
            isLiquid: isLiquid,
            servingLabel: servingLabel,
            servingSize: servingSize,
            packageSize: packageSize,
            nutrientsJson: nutrientsJson,
            modifiedAt: modifiedAt,
            scans: scans,
            origin: origin,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OpenFoodFactsProductsTableProcessedTableManager
    = ProcessedTableManager<
        _$FoodReferenceDatabase,
        $OpenFoodFactsProductsTable,
        OpenFoodFactsProductRow,
        $$OpenFoodFactsProductsTableFilterComposer,
        $$OpenFoodFactsProductsTableOrderingComposer,
        $$OpenFoodFactsProductsTableAnnotationComposer,
        $$OpenFoodFactsProductsTableCreateCompanionBuilder,
        $$OpenFoodFactsProductsTableUpdateCompanionBuilder,
        (
          OpenFoodFactsProductRow,
          BaseReferences<_$FoodReferenceDatabase, $OpenFoodFactsProductsTable,
              OpenFoodFactsProductRow>
        ),
        OpenFoodFactsProductRow,
        PrefetchHooks Function()>;

class $FoodReferenceDatabaseManager {
  final _$FoodReferenceDatabase _db;
  $FoodReferenceDatabaseManager(this._db);
  $$ReferenceMetaTableTableManager get referenceMeta =>
      $$ReferenceMetaTableTableManager(_db, _db.referenceMeta);
  $$OpenFoodFactsProductsTableTableManager get openFoodFactsProducts =>
      $$OpenFoodFactsProductsTableTableManager(_db, _db.openFoodFactsProducts);
}
