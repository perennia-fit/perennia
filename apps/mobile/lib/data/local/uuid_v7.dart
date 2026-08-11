import 'dart:math';

class UuidV7Generator {
  UuidV7Generator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  int _lastTimestampMs = -1;
  int _sequence = 0;

  String generate({DateTime? timestamp}) {
    final unixMilliseconds =
        (timestamp ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final orderedMilliseconds = _nextOrderedTimestamp(unixMilliseconds);

    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[0] = (orderedMilliseconds >> 40) & 0xff;
    bytes[1] = (orderedMilliseconds >> 32) & 0xff;
    bytes[2] = (orderedMilliseconds >> 24) & 0xff;
    bytes[3] = (orderedMilliseconds >> 16) & 0xff;
    bytes[4] = (orderedMilliseconds >> 8) & 0xff;
    bytes[5] = orderedMilliseconds & 0xff;
    bytes[6] = 0x70 | ((_sequence >> 8) & 0x0f);
    bytes[7] = _sequence & 0xff;
    bytes[8] = 0x80 | (bytes[8] & 0x3f);

    return _formatUuid(bytes);
  }

  int _nextOrderedTimestamp(int timestampMs) {
    if (timestampMs > _lastTimestampMs) {
      _lastTimestampMs = timestampMs;
      _sequence = 0;
      return timestampMs;
    }

    _sequence += 1;
    if (_sequence <= 0x0fff) {
      return _lastTimestampMs;
    }

    _lastTimestampMs += 1;
    _sequence = 0;
    return _lastTimestampMs;
  }

  String _formatUuid(List<int> bytes) {
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
