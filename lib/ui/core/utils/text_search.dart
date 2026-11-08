/// Texto comparable para buscadores: minúsculas, sin tildes ni diéresis (ñ→n) y con espacios simples.
/// "María  José" y "maria jose" dan el mismo resultado.
String foldText(String? text) {
  if (text == null || text.isEmpty) return '';
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in text.toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// true si [haystack] contiene [query] ignorando mayúsculas, tildes y espacios repetidos.
bool foldContains(String? haystack, String query) => foldText(haystack).contains(foldText(query));
