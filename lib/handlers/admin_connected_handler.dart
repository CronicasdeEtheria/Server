// lib/handlers/admin_log_handler.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_web_socket/src/web_socket_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Broadcaster que abre un solo FileSystemEvent.watch
/// y reparte cada línea nueva a todos los suscriptores.
class LogBroadcaster {
  static final LogBroadcaster _instance = LogBroadcaster._();
  factory LogBroadcaster() => _instance;

  final StreamController<String> _ctrl = StreamController.broadcast();
  RandomAccessFile? _raf;
  int _lastOffset = 0;

  LogBroadcaster._() {
    _startWatching();
  }

  void _startWatching() async {
    final path = Platform.environment['LOG_PATH'] ?? 'logs/server.log';
    final file = File(path);

    // Si no existe, intentamos crear padre para evitar errores
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.createSync();
    }

    // Abrimos el file para lecturas incrementales
    _raf = await file.open(mode: FileMode.read);
    _lastOffset = await _raf!.length();

    // Watch para detectar modificaciones
    file.watch(events: FileSystemEvent.modify).listen((_) async {
      final newLength = await _raf!.length();
      if (newLength > _lastOffset) {
        // Leemos sólo lo añadido
        await _raf!.setPosition(_lastOffset);
        final added = await _raf!.read(newLength - _lastOffset);
        _lastOffset = newLength;
        // Convertimos bytes a líneas y emitimos cada una
        final text = utf8.decode(added);
        for (var line in const LineSplitter().convert(text)) {
          _ctrl.add(line);
        }
      }
    });
  }

  /// Stream broadcast con cada línea nueva
  Stream<String> get lines => _ctrl.stream;
}

/// El handler que montas en /ws/log
FutureOr<Response> wsLogHandler(Request request) {
  return webSocketHandler((WebSocketChannel ws) async {
    final path = Platform.environment['LOG_PATH'] ?? 'logs/server.log';
    final file = File(path);

    // Al conectar, enviamos las últimas 100 líneas
    if (file.existsSync()) {
      final allLines = await file.readAsLines();
      final tail = allLines.length > 100
        ? allLines.sublist(allLines.length - 100)
        : allLines;
      for (var line in tail) {
        ws.sink.add(line);
      }
    }

    // Luego nos suscribimos al broadcast
    final sub = LogBroadcaster().lines.listen(ws.sink.add);

    // Al cerrar el socket, cancelamos la suscripción
    ws.stream.listen(
      (_) {},
      onDone: () => sub.cancel(),
      onError: (_) => sub.cancel(),
    );
  } as ConnectionCallback)(request);
}
