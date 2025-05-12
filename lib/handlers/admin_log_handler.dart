// lib/handlers/log_ws_handler.dart
import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
FutureOr<Response> logWebSocketHandler(Request request) {
  final logPath = Platform.environment['LOG_PATH'] ?? 'logs/server.log';
  final file = File(logPath);

  return webSocketHandler((WebSocketChannel ws, String? protocol) {
    // 1) Al conectar, envío las últimas 100 líneas
    if (file.existsSync()) {
      final lines = file.readAsLinesSync();
      final tail = lines.length > 100
          ? lines.sublist(lines.length - 100)
          : lines;
      for (var l in tail) ws.sink.add(l);
    }

    // 2) Luego “escucho” modificaciones y envío solo la línea nueva
    final sub = file.watch(events: FileSystemEvent.modify).listen((_) {
      final all = file.readAsLinesSync();
      if (all.isNotEmpty) ws.sink.add(all.last);
    });

    // Cuando el cliente cierro, cancelamos la escucha
    ws.stream.listen((_) {}, onDone: () => sub.cancel());
  })(request);
}
