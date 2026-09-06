import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/tts_endpoint.dart';

/// El techo de síntesis de Chatterbox sale de lo que la máquina viene
/// tardando, no de un número calibrado en otro hardware. La regla que importa
/// es que esto solo puede volver la app **más** paciente: el caso que motivó
/// el cambio es una GPU justa terminando un párrafo que el cliente ya había
/// tirado a la basura (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
void main() {
  test('sin mediciones todavía, el presupuesto es el de siempre', () {
    expect(
      TtsTimeouts.adaptiveSynthesis(measured: Duration.zero, samples: 0),
      TtsTimeouts.synthesisChatterbox,
    );
  });

  test('una medición absurda (cero) no colapsa el presupuesto a nada', () {
    // Defensivo: un cronómetro que devuelve cero no puede traducirse en
    // "ríndete de inmediato", que es justo el fallo que se quiere evitar.
    expect(
      TtsTimeouts.adaptiveSynthesis(measured: Duration.zero, samples: 3),
      TtsTimeouts.synthesisChatterbox,
    );
  });

  test('una máquina rápida no vuelve la app menos paciente que hoy', () {
    // 30 s por párrafo x5 = 150 s, por debajo del suelo: se queda en 240 s.
    expect(
      TtsTimeouts.adaptiveSynthesis(
          measured: const Duration(seconds: 30), samples: 4),
      TtsTimeouts.synthesisChatterbox,
    );
  });

  test('una GPU justa estira el techo cinco veces lo medido', () {
    expect(
      TtsTimeouts.adaptiveSynthesis(
          measured: const Duration(seconds: 90), samples: 4),
      const Duration(seconds: 450),
    );
  });

  test('el caso real del incidente queda cubierto con margen', () {
    // El párrafo abandonado tardó 4 m 37 s. Con un promedio de 90 s medido,
    // el techo es 7 m 30 s: ese párrafo se habría completado en vez de
    // perderse.
    final techo = TtsTimeouts.adaptiveSynthesis(
        measured: const Duration(seconds: 90), samples: 5);
    expect(techo, greaterThan(const Duration(minutes: 4, seconds: 37)));
  });

  test('una racha lenta no se convierte en una espera de media hora', () {
    expect(
      TtsTimeouts.adaptiveSynthesis(
          measured: const Duration(minutes: 10), samples: 6),
      TtsTimeouts.adaptiveSynthesisCeiling,
    );
  });
}
