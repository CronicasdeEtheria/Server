import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_web_socket/src/web_socket_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:guildserver/db/db.dart';

/// Broadcaster singleton (igual que para el log)
class _ChatBroadcaster {
  static final _ChatBroadcaster _inst = _ChatBroadcaster._();
  factory _ChatBroadcaster() => _inst;
  final StreamController<Map<String, dynamic>> _ctrl =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get stream => _ctrl.stream;
  void add(Map<String, dynamic> msg) => _ctrl.add(msg);
  _ChatBroadcaster._();
}

FutureOr<Response> chatWebSocketHandler(Request req) =>
  webSocketHandler((WebSocketChannel ws) async {
    // 1) al conectar: envío historial
    final conn = await getConnection();
    final result = await conn.execute('''
      SELECT username, message, timestamp
        FROM chat_global
      ORDER BY timestamp DESC
      LIMIT 50
    ''');
    final history = result.rows
        .map((r) => {
              'type': 'message',
              'username': r.colAt(0),
              'message': r.colAt(1),
              'timestamp': DateTime.parse(r.colAt(2)!).toIso8601String(),
            })
        .toList()
        .reversed
        .toList();
    for (var msg in history) {
      ws.sink.add(jsonEncode(msg));
    }

    // 2) suscripción a nuevos mensajes
    final sub = _ChatBroadcaster().stream.listen((msg) {
      ws.sink.add(jsonEncode(msg));
    });

    // 3) limpio al desconectarse
    ws.stream.listen((_) {}, onDone: () => sub.cancel());
  } as ConnectionCallback)(req);
