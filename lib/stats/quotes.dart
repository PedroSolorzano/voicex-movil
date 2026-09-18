/// Quotes about reading, one per day.
///
/// Curated for attribution rather than for number: a good share of the
/// "famous reading quotes" that circulate were never said by who they are
/// pinned on (Twain, Hemingway, Santa Teresa, Cicero's "room without books").
/// Each one here has a known source, noted next to it. Where the original is
/// not Spanish the wording is a translation.
library;

typedef Quote = ({String text, String author});

const quotes = <Quote>[
  // Poema de los dones.
  (
    text: 'Yo, que me figuraba el Paraíso bajo la especie de una biblioteca.',
    author: 'Jorge Luis Borges',
  ),
  // Don Quijote, II, 25.
  (
    text: 'El que lee mucho y anda mucho, ve mucho y sabe mucho.',
    author: 'Miguel de Cervantes',
  ),
  // «Un lector», Elogio de la sombra.
  (
    text: 'Que otros se jacten de las páginas que han escrito; '
        'a mí me enorgullecen las que he leído.',
    author: 'Jorge Luis Borges',
  ),
  // Soneto «Desde la Torre».
  (
    text: 'Vivo en conversación con los difuntos '
        'y escucho con mis ojos a los muertos.',
    author: 'Francisco de Quevedo',
  ),
  // Carta a Oskar Pollak, 1904.
  (
    text: 'Un libro debe ser el hacha que rompa el mar helado '
        'que llevamos dentro.',
    author: 'Franz Kafka',
  ),
  // Carta a su nieto, L'Espresso, 2014.
  (
    text: 'Quien no lee, a los setenta años habrá vivido una sola vida: '
        'la propia. Quien lee habrá vivido cinco mil años.',
    author: 'Umberto Eco',
  ),
  // Libro del desasosiego.
  (text: 'Leer es soñar de la mano de otro.', author: 'Fernando Pessoa'),
  // The Tatler, n.º 147, 1710.
  (
    text: 'La lectura es a la mente lo que el ejercicio es al cuerpo.',
    author: 'Richard Steele',
  ),
  // La sombra del viento.
  (
    text: 'Los libros son espejos: solo se ve en ellos lo que uno ya lleva '
        'dentro.',
    author: 'Carlos Ruiz Zafón',
  ),
  // Por qué leer los clásicos.
  (
    text: 'Un clásico es un libro que nunca termina de decir lo que tiene '
        'que decir.',
    author: 'Italo Calvino',
  ),
  // Discurso del método, primera parte.
  (
    text: 'La lectura de todos los buenos libros es como una conversación '
        'con los mejores hombres de los siglos pasados.',
    author: 'René Descartes',
  ),
  // I Can Read with My Eyes Shut!
  (
    text: 'Cuanto más leas, más cosas sabrás. Cuanto más aprendas, '
        'a más lugares irás.',
    author: 'Dr. Seuss',
  ),
  // Poema 1263.
  (
    text: 'No hay fragata como un libro para llevarnos a tierras lejanas.',
    author: 'Emily Dickinson',
  ),
  // Of Studies.
  (
    text: 'La lectura hace al hombre completo; la conversación, ágil; '
        'y la escritura, preciso.',
    author: 'Francis Bacon',
  ),
  // Danza de dragones.
  (
    text: 'Un lector vive mil vidas antes de morir. '
        'El que nunca lee vive solo una.',
    author: 'George R. R. Martin',
  ),
  // Ad familiares, IX, 4.
  (
    text: 'Si junto a la biblioteca tienes un jardín, nada te faltará.',
    author: 'Cicerón',
  ),
  // Mes pensées.
  (
    text: 'Nunca he tenido una pena que una hora de lectura no me haya '
        'quitado.',
    author: 'Montesquieu',
  ),
  // «How Should One Read a Book?» — el juicio final de los lectores.
  (
    text: 'Estos no necesitan recompensa. No tenemos nada que darles aquí. '
        'Han amado la lectura.',
    author: 'Virginia Woolf',
  ),
  // Respuesta a sor Filotea de la Cruz.
  (
    text: 'No estudio para saber más, sino para ignorar menos.',
    author: 'Sor Juana Inés de la Cruz',
  ),
  // Sobre la lectura.
  (
    text: 'La lectura es ese milagro fecundo de una comunicación en el seno '
        'de la soledad.',
    author: 'Marcel Proust',
  ),
  // The Durable Satisfactions of Life.
  (
    text: 'Los libros son los amigos más silenciosos y constantes, '
        'y los maestros más pacientes.',
    author: 'Charles W. Eliot',
  ),
  // Citado por Walter Hooper.
  (
    text: 'No hay taza de té lo bastante grande ni libro lo bastante largo '
        'para mí.',
    author: 'C. S. Lewis',
  ),
  // Mientras escribo.
  (
    text: 'Los libros son una magia singularmente portátil.',
    author: 'Stephen King',
  ),
  // «El libro», Borges oral.
  (
    text: 'De los diversos instrumentos del hombre, el más asombroso es, '
        'sin duda, el libro.',
    author: 'Jorge Luis Borges',
  ),
  // Discurso del Nobel, «Elogio de la lectura y la ficción», 2010.
  (
    text: 'Aprendí a leer a los cinco años. Es la cosa más importante que me '
        'ha pasado en la vida.',
    author: 'Mario Vargas Llosa',
  ),
  // Matar a un ruiseñor.
  (
    text: 'Hasta que temí perderla, nunca amé la lectura. '
        'Uno no ama respirar.',
    author: 'Harper Lee',
  ),
  // Tokio blues.
  (
    text: 'Si solo lees los libros que todos leen, solo podrás pensar lo que '
        'todos piensan.',
    author: 'Haruki Murakami',
  ),
  // Don Quijote, I, 9.
  (
    text: 'Yo soy aficionado a leer, aunque sean los papeles rotos de las '
        'calles.',
    author: 'Miguel de Cervantes',
  ),
];

/// The same quote all day, a different one tomorrow.
///
/// Counted from calendar days rather than picked at random, so reopening the
/// progress screen does not reshuffle it like a slot machine.
Quote quoteForDay(DateTime day) {
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(2000))
      .inDays;
  return quotes[days % quotes.length];
}
