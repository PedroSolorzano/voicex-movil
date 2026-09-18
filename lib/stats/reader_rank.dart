/// Reader ranks: a title and a level earned by pages read or heard.
///
/// Pages rather than minutes or paragraphs: a page is the same length whatever
/// the font size or the voice's speed, and "40 pages" needs no explaining.
/// Only ever goes up — there is nothing here to lose.
class ReaderRank {
  /// The publishing convention for a page of prose.
  static const charsPerPage = 1800;

  /// Level `n` starts at `pagesStep * n * (n - 1) / 2` pages: 0, 40, 120, 240…
  /// Each level asks for 40 more pages than the last, so the early ones come
  /// quickly and the later ones mean something. A novel is ~300 pages, so
  /// level 10 is about six novels in.
  static const pagesStep = 40;

  /// Titles for levels 1 to 10. Past that, the last one with a Roman numeral.
  /// Changing them touches no logic.
  static const titles = [
    'Lector novel',
    'Aprendiz',
    'Lector',
    'Lector asiduo',
    'Devorador de libros',
    'Ratón de biblioteca',
    'Bibliófilo',
    'Erudito',
    'Bibliotecario',
    'Maestro bibliotecario',
  ];

  static double pagesOf(int chars) => chars / charsPerPage;

  /// Pages needed to reach [level].
  static int threshold(int level) =>
      level <= 1 ? 0 : pagesStep * level * (level - 1) ~/ 2;

  static int levelFor(double pages) {
    var level = 1;
    while (pages >= threshold(level + 1)) {
      level++;
    }
    return level;
  }

  static String titleFor(int level) {
    if (level <= titles.length) return titles[level - 1];
    return '${titles.last} ${roman(level - titles.length + 1)}';
  }

  /// How far through the current level, from 0 to 1.
  static double progressToNext(double pages) {
    final level = levelFor(pages);
    final from = threshold(level);
    final to = threshold(level + 1);
    return ((pages - from) / (to - from)).clamp(0.0, 1.0);
  }

  /// Also numbers the lots of the classic library skin.
  static String roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I',
    ];
    final out = StringBuffer();
    var rest = n;
    for (var i = 0; i < values.length; i++) {
      while (rest >= values[i]) {
        out.write(symbols[i]);
        rest -= values[i];
      }
    }
    return out.toString();
  }
}
