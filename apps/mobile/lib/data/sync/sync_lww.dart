bool syncLwwWins(
  DateTime incomingUpdatedAt,
  String incomingDeviceId,
  DateTime existingUpdatedAt,
  String existingDeviceId,
) {
  final timestampComparison = incomingUpdatedAt.compareTo(existingUpdatedAt);
  if (timestampComparison != 0) {
    return timestampComparison > 0;
  }

  return incomingDeviceId.compareTo(existingDeviceId) > 0;
}
