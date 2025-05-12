import 'dart:convert';
import 'dart:io';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/connection_manager.dart';
/// Lista global donde guardamos todos los canales WS conectados
final List<WebSocketChannel> _chatClients = [];

/// Se llama cada vez que un cliente se conecta por WS
void _chatSocketHandler(WebSocketChannel ws) {
  _chatClients.add(ws);
  ws.stream.listen((_) {
    // si quisieras procesar mensajes entrantes del cliente, va aquí
  }, onDone: () {
    _chatClients.remove(ws);
  });
}

Future<Response> adminConnectedUsersHandler(Request request) async {
  final uids = connectionManager.connectedUids;
  if (uids.isEmpty) return Response.ok(jsonEncode([]));

  try {
    final conn = await getConnection();

    // Construimos los marcadores de posición para la cláusula IN
    final placeholders = List.filled(uids.length, '?').join(', ');
    final query = '''
      SELECT u.id, u.username, u.email, u.elo, u.race, g.name
      FROM users u
      LEFT JOIN guild_members gm ON gm.user_id = u.id
      LEFT JOIN guilds g ON g.id = gm.guild_id
      WHERE u.id IN ($placeholders)
    ''';

    // Preparamos la sentencia
    final stmt = await conn.prepare(query);

    // Ejecutamos la sentencia con los parámetros
    final results = await stmt.execute(uids);

    final users = results.rows.map((row) => {
      'uid': row.colAt(0),
      'username': row.colAt(1),
      'email': row.colAt(2),
      'elo': int.tryParse(row.colAt(3) ?? '0') ?? 0,
      'race': row.colAt(4),
      'guild': row.colAt(5),
    }).toList();

    // Liberamos la sentencia preparada
    await stmt.deallocate();

    return Response.ok(jsonEncode(users));
  } catch (e, st) {
    print('❌ Error en /admin/connected_users: $e');
    print(st);
    return Response.internalServerError(
      body: jsonEncode({
        'error': 'Error al obtener usuarios conectados',
        'details': e.toString()
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> adminLogHandler(Request req) async {
  const logPath = '/var/log/etheria/server.log'; // ajústalo
  final file = File(logPath);
  if (!await file.exists()) {
    return Response.notFound(
      jsonEncode({'error': 'Log no encontrado'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
  final lines = await file.readAsLines();
  final recent = lines.length > 200
      ? lines.sublist(lines.length - 200)
      : lines;
  return Response.ok(
    jsonEncode({'lines': recent}),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Response> adminRestartHandler(Request req) async {
  try {
    await Process.run('systemctl', ['restart', 'minecraft']); // o tu comando
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'success': false, 'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> adminBroadcastHandler(Request req) async {
  final payload = jsonDecode(await req.readAsString());
  final msg = payload['message']?.toString() ?? '';
  final event = jsonEncode({
    'user': 'SERVER',
    'message': msg,
    'ts': DateTime.now().toUtc().toIso8601String(),
  });
  for (var client in _chatClients) {
    client.sink.add(event);
  }
  return Response.ok(
    jsonEncode({'success': true}),
    headers: {'Content-Type': 'application/json'},
  );
}