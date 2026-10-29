/// HE / SHE FOR EVERY STUDENT (the same rule as `functions/pronouns.js`): text about a student uses his or her own pronouns from the user
/// record's `gender` ("male" / "female"). The templates are written in the masculine; [pronouned] says one for the student it is about:
///
///   male      unchanged
///   female    he -> she, him -> her, his -> her (hers when it stands alone), himself -> herself, he's -> she's, boy(s) -> girl(s)
///   missing   never guessed: the first name stands in ("Ravi is struggling", "Ravi's sadhana"), "themselves", "student"
String pronouned(String text, String? gender, {String name = ''}) {
  final g = (gender ?? '').trim().toLowerCase();
  if (g == 'male' || text.isEmpty) return text;
  String keep(Match m, String to) {
    final w = m[0]!;
    final upper = w[0] == w[0].toUpperCase() && w[0] != w[0].toLowerCase();
    return upper ? '${to[0].toUpperCase()}${to.substring(1)}' : to;
  }

  if (g == 'female') {
    return text
        .replaceAllMapped(RegExp(r"\bhe's\b", caseSensitive: false), (m) => keep(m, "she's"))
        .replaceAllMapped(RegExp(r'\bhimself\b', caseSensitive: false), (m) => keep(m, 'herself'))
        .replaceAllMapped(RegExp(r'\bhis\b(?=\s*(?:[.,;:!?)]|$))', caseSensitive: false), (m) => keep(m, 'hers'))
        .replaceAllMapped(RegExp(r'\bhis\b', caseSensitive: false), (m) => keep(m, 'her'))
        .replaceAllMapped(RegExp(r'\bhim\b', caseSensitive: false), (m) => keep(m, 'her'))
        .replaceAllMapped(RegExp(r'\bhe\b', caseSensitive: false), (m) => keep(m, 'she'))
        .replaceAllMapped(RegExp(r'\bboys\b', caseSensitive: false), (m) => keep(m, 'girls'))
        .replaceAllMapped(RegExp(r'\bboy\b', caseSensitive: false), (m) => keep(m, 'girl'));
  }
  final first = name.trim().split(RegExp(r'\s+')).first;
  final who = first.isEmpty ? 'the student' : first;
  return text
      .replaceAllMapped(RegExp(r"\bhe's\b", caseSensitive: false), (m) => '$who is')
      .replaceAll(RegExp(r'\bhimself\b', caseSensitive: false), 'themselves')
      .replaceAllMapped(RegExp(r'\bhis\b', caseSensitive: false), (m) => "$who's")
      .replaceAllMapped(RegExp(r'\bhim\b', caseSensitive: false), (m) => who)
      .replaceAllMapped(RegExp(r'\bhe\b', caseSensitive: false), (m) => who)
      .replaceAll(RegExp(r'\bboys\b', caseSensitive: false), 'students')
      .replaceAll(RegExp(r'\bboy\b', caseSensitive: false), 'student');
}
