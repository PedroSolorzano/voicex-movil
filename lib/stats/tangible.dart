/// Turns a page count into something that can be pictured.
///
/// "1,240 pages" says little; "a bit more than one Quijote" says a lot. The
/// comparison is always against books, never against people: a list of famous
/// readers' habits would show everyone losing every day, which is the
/// opposite of what a reward is for.
library;

/// Works almost everyone can place, with a round page count for a common
/// Spanish edition. Approximate on purpose — the phrase says "≈" — and ordered
/// short to long.
const referenceWorks = [
  (title: 'El principito', pages: 96),
  (title: 'Pedro Páramo', pages: 128),
  (title: 'Cien años de soledad', pages: 470),
  (title: 'El Quijote', pages: 1100),
  (title: 'El señor de los anillos', pages: 1200),
  (title: 'Guerra y paz', pages: 1250),
  (title: 'la saga completa de Harry Potter', pages: 4100),
];

/// A phrase comparing [pages] with one of [referenceWorks], or null when there
/// is too little read for any comparison to make sense.
///
/// Only works where the multiple lands between 0.5 and 10 are candidates, so
/// the phrase never reads "0.03 Quijotes". [seed] picks among them — pass the
/// day of the year and the comparison changes from one day to the next but
/// stays put within a day.
String? equivalence(double pages, int seed) {
  final fits = [
    for (final w in referenceWorks)
      if (pages / w.pages >= 0.5 && pages / w.pages <= 10) w,
  ];
  if (fits.isEmpty) return null;
  final work = fits[seed.abs() % fits.length];
  final times = pages / work.pages;
  if (times < 1) {
    return 'Ya leíste el ${(times * 100).round()} % de «${work.title}»';
  }
  return 'Ya leíste ${_decimal(times)} veces «${work.title}»';
}

/// Height of [pages] as a stack of paper, in centimetres: two pages to a
/// sheet, a tenth of a millimetre per sheet.
double stackHeightCm(double pages) => pages / 2 * 0.01;

/// The only figure about other people's reading the app quotes, with where it
/// comes from so it can be checked.
///
/// INEGI, *Módulo sobre Lectura (MOLEC) 2025*, comunicado de prensa 143/25
/// (18 de noviembre de 2025), p. 1: «Del total de población alfabeta de 12
/// años y más (103.9 millones), 62.5 % leyó libros» en los últimos 12 meses.
///
/// Not an average of books per person: the press has been quoting one, but
/// INEGI's release does not publish it, and the 2025 methodology change starts
/// a new series that cannot be compared with earlier years.
const nationalReference = (
  text: 'En México, 62,5 % de las personas de 12 años o más leyó al menos '
      'un libro en el último año.',
  source: 'INEGI, Módulo sobre Lectura (MOLEC) 2025',
);

String _decimal(double x) =>
    x.toStringAsFixed(x < 10 ? 1 : 0).replaceAll('.', ',');
