/// A minimal, dependency-free RFC-4180-ish CSV parser, sufficient for the
/// nutrition-import edge path (NUTRITION.md §9). Hand-rolled rather than adding
/// a package so the import slice stays mobile-only and the CI gate does not
/// pull extra jobs.
///
/// Supports quoted fields (commas/newlines inside quotes), escaped quotes
/// (`""`), CRLF and LF line endings, and a leading UTF-8 BOM. Returns one
/// `List<String>` per record; a trailing blank line yields no record.
List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[];
  if (input.isEmpty) {
    return rows;
  }

  // Strip a leading UTF-8 BOM if present.
  var text = input;
  if (text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1);
  }

  var field = StringBuffer();
  var record = <String>[];
  var inQuotes = false;
  var sawAnyField = false;

  void endField() {
    record.add(field.toString());
    field = StringBuffer();
    sawAnyField = true;
  }

  void endRecord() {
    endField();
    rows.add(record);
    record = <String>[];
    sawAnyField = false;
  }

  for (var i = 0; i < text.length; i += 1) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }

    switch (char) {
      case '"':
        inQuotes = true;
      case ',':
        endField();
      case '\r':
        // Treat CRLF (and a lone CR) as a single record terminator.
        endRecord();
        if (i + 1 < text.length && text[i + 1] == '\n') {
          i += 1;
        }
      case '\n':
        endRecord();
      default:
        field.write(char);
    }
  }

  // Flush a final record that was not newline-terminated.
  if (sawAnyField || field.isNotEmpty) {
    endRecord();
  }

  return rows;
}
