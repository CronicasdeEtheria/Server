import 'dart:convert';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';

Future<Response> chatGlobalHistoryHandler(Request request) async {
  try {
    final conn = await getConnection();

    final result = await conn.execute('''
      SELECT username, message, timestamp
      FROM chat_global
      ORDER BY timestamp DESC
      LIMIT 50
    ''');

    final messages = result.rows.map((row) => {
      'username': row.colAt(0),
      'message': row.colAt(1),
      'timestamp': DateTime.parse(row.colAt(2)!).toIso8601String(),
    }).toList().reversed.toList(); // Mostrar en orden cronológico (antiguos primero)

    return Response.ok(
      jsonEncode(messages),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response(500, body: 'Error al obtener historial: $e');
  }
}

/// Handler para enviar un mensaje al chat global.
Future<Response> chatGlobalSendHandler(Request request) async {
  try {
    // 1) Leer y decodificar body
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final message = data['message']?.toString();
    if (message == null || message.isEmpty) {
      return Response(400, body: 'Falta el campo "message".');
    }

    // 2) Obtener conexión y, opcionalmente, la info del usuario
    final conn = await getConnection();
    final uid = request.headers['uid'];
    if (uid == null) {
      return Response.forbidden('Token inválido.');
    }

    // 3) Recuperar el username desde la tabla de usuarios
    final userRes = await conn.execute(
      'SELECT username FROM users WHERE id = :uid',
      {'uid': uid},
    );
    final username = userRes.rows.first.colAt(0);

    // 4) Insertar en chat_global
    await conn.execute(
      '''
      INSERT INTO chat_global (user_id, username, message, timestamp)
      VALUES (:uid, :username, :msg, CURRENT_TIMESTAMP)
      ''',
      {
        'uid': uid,
        'username': username,
        'msg': message,
      },
    );

    // 5) Responder OK
    return Response.ok(jsonEncode({'ok': true}), headers: {
      'Content-Type': 'application/json'
    });
  } catch (e) {
    return Response.internalServerError(body: 'Error al enviar mensaje: $e');
  }
}