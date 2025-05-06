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
