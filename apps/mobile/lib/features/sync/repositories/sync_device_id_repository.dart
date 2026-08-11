import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../data/local/uuid_v7.dart';

final syncDeviceIdProvider = FutureProvider<String>((ref) {
  return FileSyncDeviceIdRepository.openDefault().loadOrCreate();
});

class FileSyncDeviceIdRepository {
  FileSyncDeviceIdRepository({
    required Future<File> Function() deviceFile,
    UuidV7Generator? uuidGenerator,
  })  : _deviceFile = deviceFile,
        _uuidGenerator = uuidGenerator ?? UuidV7Generator();

  factory FileSyncDeviceIdRepository.openDefault({
    UuidV7Generator? uuidGenerator,
  }) {
    return FileSyncDeviceIdRepository(
      deviceFile: _defaultDeviceFile,
      uuidGenerator: uuidGenerator,
    );
  }

  final Future<File> Function() _deviceFile;
  final UuidV7Generator _uuidGenerator;

  Future<String> loadOrCreate() async {
    final file = await _deviceFile();
    final existing = await _readExisting(file);
    if (existing != null) {
      return existing;
    }

    final deviceId = 'mobile:${_uuidGenerator.generate()}';
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'deviceId': deviceId,
      }),
    );
    return deviceId;
  }

  Future<String?> _readExisting(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return _validDeviceId(decoded['deviceId']);
      }
    } on Object {
      return null;
    }
    return null;
  }

  String? _validDeviceId(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<File> _defaultDeviceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'sync_device_id.json'));
  }
}
