import 'dart:convert';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import '../services/connection_manager.dart';

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
