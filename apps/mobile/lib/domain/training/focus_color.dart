import 'dart:convert';

/// The seeded ids of the starter Focuses.
const starterFocusWeightsId = '01910000-0000-7000-8000-000000000401';
const starterFocusEnduranceId = '01910000-0000-7000-8000-000000000402';
const starterFocusFunctionalId = '01910000-0000-7000-8000-000000000403';
const starterFocusCalisthenicsId = '01910000-0000-7000-8000-000000000404';
const starterFocusMobilityId = '01910000-0000-7000-8000-000000000405';

const _starterFocusColorTokens = <String, String>{
  starterFocusWeightsId: 'back',
  starterFocusEnduranceId: 'cardio',
  starterFocusFunctionalId: 'shoulders',
  starterFocusCalisthenicsId: 'arms',
  starterFocusMobilityId: 'core',
};

/// The category tokens a Focus may take, in the order the color dialog offers
/// them. `other` is left out: Time by Focus uses it for "No Focus".
const focusColorTokens = <String>[
  'back',
  'cardio',
  'core',
  'shoulders',
  'arms',
  'legs',
  'chest',
];

/// The DESIGN.md category token a Focus uses until the user picks a color
/// (docs/designs/progress-overview.md, D6). It depends only on the id, so
/// reordering or renaming never recolors a Focus, and every device agrees
/// without storing or syncing it.
String focusDefaultColorToken(String focusId) {
  return _starterFocusColorTokens[focusId] ??
      focusColorTokens[fnv1a32(focusId) % focusColorTokens.length];
}

/// The 32-bit FNV-1a hash of [value]'s UTF-8 bytes.
int fnv1a32(String value) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
