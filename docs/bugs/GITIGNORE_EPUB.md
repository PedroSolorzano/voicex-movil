# `.gitignore` capturaba `lib/epub/` — `text_align.dart` nunca llegó a git

**Archivo afectado:** `.gitignore` (línea 45, antes del fix)
**Síntoma:** `flutter analyze` y `flutter test` fallan en cualquier checkout
limpio con decenas de errores en `lib/ui/providers/reader_provider.dart`,
`lib/ui/screens/reader_screen.dart` y `test/text_align_test.dart`: tipos
inexistentes (`WordMark`, `SentenceRange`) y funciones sin definir
(`activeWordIndex`, `sentenceAtOffset`, `buildWordMarks`,
`buildSentenceRanges`, `wordBoundaryAt`).

---

## Causa

La regla `epub/` (sin barra inicial) le dice a Git "ignorá cualquier carpeta
llamada `epub` en todo el árbol", no solo la de la raíz. El comentario de al
lado ("Test EPUBs, libros de prueba, no van al repo") deja claro que la
intención era ignorar `./epub/` — la carpeta de libros de prueba descargados a
mano —, pero el patrón también capturó `lib/epub/`, que es código fuente real.

`lib/epub/models.dart` y `lib/epub/parser.dart` ya estaban versionados antes
de que existiera esa regla, así que Git no los deshizo (ignorar un patrón
nunca destrackea lo ya trackeado). Pero `lib/epub/text_align.dart` —el módulo
de resaltado por palabra/oración, con `WordMark`, `SentenceRange`,
`buildWordMarks`, `buildSentenceRanges`, `activeWordIndex`,
`sentenceAtOffset`, `wordBoundaryAt`— se creó **después**, y cualquier
`git add` sobre él se descartó en silencio sin avisar.

Confirmado con `git log --oneline --all -- lib/epub/text_align.dart`: cero
resultados, en ninguna rama. El archivo no está en ningún commit del repo —
solo existe (o existía) como archivo local sin trackear en la máquina donde
se escribió originalmente.

## Impacto

No es un problema de esta laptop puntual: **cualquier clon limpio del repo no
compila**, porque `reader_provider.dart` y `reader_screen.dart` importan
`../../epub/text_align.dart` y usan sus tipos y funciones. Los commits que
agregaron esa lógica (`9caf597` "Fase 3: resaltado por palabra..." y
posteriores) se hicieron con el archivo presente en el working tree de esa
máquina, pero nunca viajó a git.

## Fix

`.gitignore`: `epub/` → `/epub/`, para anclarlo a la raíz del repo y dejar
`lib/epub/` fuera del patrón. Se hizo dos veces en paralelo, sin coordinar:
una vez en esta laptop y otra —minutos después, con el mismo cambio exacto—
en la máquina de escritorio, que además traía consigo
`lib/epub/text_align.dart` (commit `ae48fd8`). `git pull` trajo ambas cosas;
el arreglo local de esta laptop quedó descartado por redundante.
