import 'dart:io';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

FutureOr<Response> wsLogHandler(Request request) { 
  final logPath = Platform.environment['LOG_PATH'] ?? 'logs/server.log';
  final file = File(logPath);

  return webSocketHandler((webSocket, protocols) {
    if (file.existsSync()) {
      final lines = file.readAsLinesSync();
      final tail = lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
      for (var line in tail) {
        webSocket.sink.add(line);
      }
    }

    final subscription = file.watch(events: FileSystemEvent.modify).listen((_) {
      final all = file.readAsLinesSync();
      if (all.isNotEmpty) {
        webSocket.sink.add(all.last);
      }
    });

    webSocket.stream.listen((_) {}, onDone: () => subscription.cancel());
  })(request);
}
