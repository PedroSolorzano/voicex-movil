import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/tts_endpoint.dart';

/// El techo de síntesis de F5 sale de lo que la máquina viene
/// tardando, no de un número calibrado en otro hardware. La regla que importa
/// es que esto solo puede volver la app **más** paciente: el caso que motivó
/// el cambio es una GPU justa terminando un párrafo que el cliente ya había
/// tirado a la basura (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
void main() {
  test('sin mediciones todavía, el presupuesto es el de siempre', () {
    expect(
      TtsTimeouts.adaptiveSynthesis(measured: Duration.zero, samples: 0),
      TtsTimeouts.synthesisF5,
    );
  });

  test('una medición absurda (cero) no colapsa el presupuesto a nada', () {
    // Defensivo: un cronómetro que devuelve cero no puede traducirse en
    // "ríndete de inmediato", que es justo el fallo que se quiere evitar.
    expect(
      TtsTimeouts.adaptiveSynthesis(measured: Duration.zero, samples: 3),
      TtsTimeouts.synthesisF5,
    );
  });

  test('una máquina rápida no vuelve la app menos paciente que hoy', () {
    // 20 s por párrafo x5 = 100 s, por debajo del suelo de 120 s: se queda en
    // el presupuesto de siempre en vez de recortarlo.
    expect(
      TtsTimeouts.adaptiveSynthesis(
          measured: const Duration(seconds: 20), samples: 4),
      TtsTimeouts.synthesisF5,
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

  group('presupuesto por largo del texto', () {
    // Este grupo existe por un fallo real: el presupuesto fijo se calibró con
    // un párrafo de 29 s de audio, y se quedó corto con la sinopsis de la
    // contraportada de La Odisea -- cuatro veces más larga. La descarga la
    // abandonó a mitad, con el servidor generándola igual.
    test('un párrafo corto se queda en el piso', () {
      expect(
        TtsTimeouts.synthesisForChars(200),
        TtsTimeouts.synthesisF5,
        reason: '200 caracteres x 250 ms = 50 s, por debajo del piso',
      );
    });

    test('un párrafo largo recibe presupuesto proporcional', () {
      // 1.200 caracteres, del tamaño de la sinopsis que falló.
      expect(
        TtsTimeouts.synthesisForChars(1200),
        const Duration(seconds: 300),
      );
    });

    test('el presupuesto medido cubre lo que de verdad tardó', () {
      // Medido: 2.100 caracteres tardaron 291 s en la RTX 4050.
      final techo = TtsTimeouts.synthesisForChars(2100);
      expect(techo, greaterThan(const Duration(seconds: 291)));
    });

    test('un texto desmedido no dispara una espera infinita', () {
      expect(
        TtsTimeouts.synthesisForChars(1000000),
        TtsTimeouts.adaptiveSynthesisCeiling,
      );
    });

    test('el piso lo puede subir la descarga, nunca bajarlo', () {
      // Lo que mide una descarga entra como piso: si esta máquina viene
      // tardando más, el texto corto también recibe ese margen.
      expect(
        TtsTimeouts.synthesisForChars(200,
            floor: const Duration(seconds: 400)),
        const Duration(seconds: 400),
      );
    });
  });

  test('una racha lenta no se convierte en una espera de media hora', () {
    expect(
      TtsTimeouts.adaptiveSynthesis(
          measured: const Duration(minutes: 10), samples: 6),
      TtsTimeouts.adaptiveSynthesisCeiling,
    );
  });
}
