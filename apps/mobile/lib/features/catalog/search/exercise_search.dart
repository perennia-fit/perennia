bool exerciseNameMatchesQuery(String name, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) {
    return true;
  }

  final searchableName = name.toLowerCase();
  return terms.every(searchableName.contains);
}
