import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../services/reporter.dart';
import '../providers/reader_provider.dart';

const _uuid = Uuid();

/// Máximo de una nota de voz. Suficiente para contar un problema, corto para
/// que el archivo quepa en el límite del proxy.
const _maxNota = Duration(seconds: 90);

/// Contar un problema o pedir una mejora, escrito o hablado.
///
/// El contexto —libro, capítulo, motor en uso y últimos sondeos— se adjunta
/// solo. Es lo que convierte un "no sonaba" en algo accionable: dirá que el
/// sondeo tardó cuatro segundos y cayó a Edge.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _texto = TextEditingController();
  final _grabador = AudioRecorder();

  String _tipo = 'bug';
  bool _grabando = false;
  String? _notaPath;
  int _segundos = 0;
  Timer? _cronometro;
  bool _enviado = false;

  @override
  void dispose() {
    _cronometro?.cancel();
    _texto.dispose();
    unawaited(_grabador.dispose());
    super.dispose();
  }

  Future<void> _alternarGrabacion() async {
    if (_grabando) {
      final path = await _grabador.stop();
      _cronometro?.cancel();
      if (!mounted) return;
      setState(() {
        _grabando = false;
        _notaPath = path;
      });
      return;
    }

    // El permiso se pide aquí, al pulsar grabar, y no al arrancar la app:
    // ésta es la única función que necesita el micrófono, y es el primer
    // permiso que la app pide de su vida.
    if (!await _grabador.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sin permiso de micrófono no se puede grabar. '
            'Puedes escribirlo igualmente.'),
      ));
      return;
    }

    final dir = await getTemporaryDirectory();
    // El nombre lo impone el servidor con una expresión: un uuid y nada más.
    final path = '${dir.path}/${_uuid.v4()}.m4a';
    await _grabador.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _grabando = true;
      _segundos = 0;
      _notaPath = null;
    });
    _cronometro = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _segundos++);
      if (_segundos >= _maxNota.inSeconds) unawaited(_alternarGrabacion());
    });
  }

  Future<void> _enviar() async {
    final estado = ref.read(readerProvider);
    await Reporter.recordFeedback(
      tipo: _tipo,
      texto: _texto.text,
      audioPath: _notaPath,
      contexto: {
        if (estado.book != null) 'libro': estado.book!.title,
        'capitulo': estado.chapterIndex,
        'parrafo': estado.paragraphIndex,
        'motor': estado.engineLabel,
      },
    );
    if (!mounted) return;
    setState(() => _enviado = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_enviado) return _Gracias(onCerrar: () => Navigator.of(context).pop());

    final hayAlgo = _texto.text.trim().isNotEmpty || _notaPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Contar un problema')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'bug', label: Text('Algo falla')),
              ButtonSegment(value: 'mejora', label: Text('Una idea')),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _texto,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Cuéntalo con tus palabras: qué hacías y qué pasó.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          Text('O cuéntalo hablando',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Suele ser más fácil que escribirlo en el teléfono. Máximo minuto y '
            'medio.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _alternarGrabacion,
                icon: Icon(_grabando ? Icons.stop : Icons.mic),
                label: Text(_grabando ? 'Detener' : 'Grabar'),
              ),
              const SizedBox(width: 12),
              if (_grabando)
                Text('${_segundos}s',
                    style: Theme.of(context).textTheme.bodyMedium)
              else if (_notaPath != null)
                Row(children: [
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 4),
                  const Text('Nota grabada'),
                  TextButton(
                    onPressed: () async {
                      final f = File(_notaPath!);
                      if (f.existsSync()) await f.delete();
                      if (mounted) setState(() => _notaPath = null);
                    },
                    child: const Text('Borrar'),
                  ),
                ]),
            ],
          ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: hayAlgo ? _enviar : null,
            child: const Text('Enviar'),
          ),
          const SizedBox(height: 12),
          Text(
            'Se adjunta solo el libro y el capítulo en el que estabas, el motor '
            'de voz en uso y los últimos intentos de conexión. No se manda el '
            'texto del libro.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Gracias extends StatelessWidget {
  const _Gracias({required this.onCerrar});

  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Enviado')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Gracias. Si el servidor no está accesible ahora, se guarda y '
                  'se manda solo cuando vuelva.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: onCerrar, child: const Text('Cerrar')),
              ],
            ),
          ),
        ),
      );
}
