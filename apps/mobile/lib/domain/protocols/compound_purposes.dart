/// Compound Purposes (CONTEXT.md `Purpose`): the starter set, the seed tags,
/// and the name and id rules. The TypeScript twin is
/// `apps/server/src/compound-purposes.ts`; the golden vectors
/// `m40-compound-purposes` hold the two together
/// (docs/designs/compound-purposes.md, D3 and D8).
///
/// The neutral-instrument rule, narrowed: the app never classifies a Compound
/// by what it is or whether it is legal, and it has no type, class, schedule
/// or legality field anywhere. It tags only its own OTC built-in Compounds
/// with Purposes, and only with the seeded names, which record what people
/// commonly take these items for and never say that they work. Once seeded, a
/// tag belongs to the user: the user can remove it and the seed never adds it
/// again. [seedCompoundPurposeIds] therefore covers the OTC Compounds only;
/// tagging anything else is a decision for the spec that grows the library.
library;

const String _sleepId = '019200ff-0000-7000-8000-000000000101';
const String _bodyCompositionId = '019200ff-0000-7000-8000-000000000102';
const String _performanceId = '019200ff-0000-7000-8000-000000000103';
const String _recoveryId = '019200ff-0000-7000-8000-000000000104';
const String _cognitionId = '019200ff-0000-7000-8000-000000000105';
const String _generalHealthId = '019200ff-0000-7000-8000-000000000106';

/// The six Purposes every device seeds, with ids fixed so two devices seed the
/// same rows. The server merges the same set into Agent reads.
const List<({String id, String name, int sortOrder})> starterPurposes =
    <({String id, String name, int sortOrder})>[
  (id: _sleepId, name: 'Sleep', sortOrder: 0),
  (id: _bodyCompositionId, name: 'Body composition', sortOrder: 1),
  (id: _performanceId, name: 'Performance', sortOrder: 2),
  (id: _recoveryId, name: 'Recovery', sortOrder: 3),
  (id: _cognitionId, name: 'Cognition', sortOrder: 4),
  (id: _generalHealthId, name: 'General health', sortOrder: 5),
];

/// The Purposes each OTC seed Compound is tagged with, keyed by its seed id.
/// Dart only: tags reach the server as stored data, through sync.
const Map<String, List<String>> seedCompoundPurposeIds = <String, List<String>>{
  // Creatine
  '019200ff-0000-7000-8000-000000000001': <String>[_performanceId],
  // Vitamin D
  '019200ff-0000-7000-8000-000000000002': <String>[_generalHealthId],
  // Caffeine
  '019200ff-0000-7000-8000-000000000003': <String>[_performanceId],
  // Magnesium
  '019200ff-0000-7000-8000-000000000004': <String>[_sleepId],
  // Melatonin
  '019200ff-0000-7000-8000-000000000005': <String>[_sleepId],
  // Fish oil
  '019200ff-0000-7000-8000-000000000006': <String>[_generalHealthId],
};

/// The instant every seeded Purpose and OTC Compound row is stamped with, the
/// one the Focus seed uses. It is fixed so an edit made after that date on any
/// device is newer, and a device that seeds before its first pull cannot win
/// last-writer-wins over such an edit; an older edit can still lose (D3).
final DateTime compoundSeedTimestamp = DateTime.utc(2026, 10, 24);

/// Refusal codes of [validatePurposeName], shared with the agent API.
const String purposeNameRequiredCode = 'purpose_name_required';
const String duplicatePurposeNameCode = 'duplicate_purpose_name';

/// A Purpose name [validatePurposeName] hard-rejected. There is no soft tier.
class PurposeNameException implements Exception {
  const PurposeNameException(this.code, this.name);

  /// [purposeNameRequiredCode] or [duplicatePurposeNameCode].
  final String code;
  final String name;

  @override
  String toString() => 'PurposeNameException($code): $name';
}

/// What two Purpose names are compared by: trimmed and case-insensitive.
String purposeNameKey(String name) => name.trim().toLowerCase();

/// Collapses repeated ids, keeping the first occurrence and the order. Never
/// sorts: the list keeps the order the user tagged in.
List<String> normalizePurposeIds(Iterable<String> ids) {
  return ids.toSet().toList(growable: false);
}

/// Returns [name] trimmed, the form it is stored in, or throws
/// [PurposeNameException]. Callers pass only active names, without the Purpose
/// being renamed, so an archived Purpose's name is free to reuse.
String validatePurposeName(
  String name,
  Iterable<String> activeNamesExcludingSelf,
) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw PurposeNameException(purposeNameRequiredCode, name);
  }
  final key = purposeNameKey(trimmed);
  if (activeNamesExcludingSelf.any((other) => purposeNameKey(other) == key)) {
    throw PurposeNameException(duplicatePurposeNameCode, name);
  }
  return trimmed;
}
