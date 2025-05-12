import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';
import '../lib/services/connection_manager.dart';

void main() async {
  final env = DotEnv()..load();
  await initDb(env);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, 808);
  print('WebSocket Chat Server listening on ws://localhost:8085');

  await for (final req in server) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      WebSocketTransformer.upgrade(req).then(handleConnection);
    } else {
      req.response
        ..statusCode = HttpStatus.forbidden
        ..close();
    }
  }
}

void handleConnection(WebSocket socket) {
  print('New connection');

  socket.listen((data) async {
    try {
      // Obtener pool de conexiones
      final pool = await getConnection();
      final msg = jsonDecode(data as String);

      if (msg['type'] == 'init') {
        final uid = msg['uid'] as String?;
        final username = msg['username'] as String?;

        if (uid == null || username == null) {
          socket.close();
          return;
        }
        connectionManager.add(uid, socket);
        print('$username ($uid) se conectó al chat');

        socket.done.then((_) {
          connectionManager.remove(uid);
          print('$username ($uid) desconectado');
        });
      }

      else if (msg['type'] == 'message') {
        final uid = msg['uid'] as String?;
        final username = msg['username'] as String?;
        final message = msg['message'] as String?;
        if (uid == null || username == null || message == null) return;
        if (!connectionManager.isOnline(uid)) return;

        final payload = {
          'type': 'message',
          'uid': uid,
          'username': username,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
        };

        // Guardar en base de datos
        await pool.execute(
          '''
          INSERT INTO chat_global (user_id, username, message)
          VALUES (:uid, :username, :message)
          ''',
          {
            'uid': uid,
            'username': username,
            'message': message,
          },
        );

        final encoded = jsonEncode(payload);
        for (final s in connectionManager.connectedSockets) {
          s.add(encoded);
        }
      }
    } catch (e) {
      print('Error en WebSocket handler: $e');
    }
  });
}
