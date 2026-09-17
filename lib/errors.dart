import 'dart:async';
import 'dart:io';

/// An error whose message was already written for the person using the app.
///
/// Most exceptions that reach a screen were written for whoever maintains the
/// library that threw them — `PathNotFoundException`, `Could not find end of
/// central directory` — and need translating before anybody reads them. This
/// one is the opposite case: the message *is* the sentence to show. The type is
/// what lets [friendlyError] pass it through instead of guessing from its
/// wording, which is the part a heuristic on accents or phrasing gets wrong the
/// first time somebody writes a message without an accent in it.
class ReadableError implements Exception {
  final String message;

  const ReadableError(this.message);

  @override
  String toString() => message;
}

/// Turns whatever failed into a sentence the reader can act on.
///
/// Four screens used to interpolate the exception straight into a SnackBar, so
/// what a tester actually read was `FormatException: Could not find end of
/// central directory`. That names the fault for a developer and tells the
/// reader nothing about what to do next.
///
/// Callers keep logging the real error next to this call: explaining the
/// failure to the reader must not cost the diagnosis.
String friendlyError(Object error) => switch (error) {
      ReadableError e => e.message,
      // Lo que lanza `epubx` cuando el archivo no es el ZIP que dice ser.
      FormatException _ => 'El archivo no parece un EPUB válido.',
      TimeoutException _ || SocketException _ =>
        'No hay conexión, o el servidor no responde.',
      FileSystemException _ =>
        'No se pudo leer el archivo. Puede que se haya movido o borrado.',
      _ => 'Algo salió mal. Si vuelve a pasar, cuéntalo desde '
          'Ajustes → Contar un problema.',
    };
