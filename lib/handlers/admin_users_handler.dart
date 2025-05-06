import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';
import 'package:guildserver/services/connection_manager.dart';

Future<Response> adminUsersHandler(Request request) async {
  try {
    final conn = await getConnection();

    final result = await conn.execute('''
      SELECT u.id, u.username, u.email, u.elo, u.race, g.name
      FROM users u
      LEFT JOIN guild_members gm ON gm.user_id = u.id
      LEFT JOIN guilds g ON g.id = gm.guild_id
    ''');

    final users = result.rows.map((row) {
      final uid = row.colAt(0)!;
      return {
        'uid': uid,
        'username': row.colAt(1),
        'email': row.colAt(2),
        'elo': int.tryParse(row.colAt(3) ?? '0'),
        'race': row.colAt(4),
        'guild': row.colAt(5),
        'online': connectionManager.isOnline(uid),
      };
    }).toList();

    print('📤 [DB] Usuarios cargados correctamente (${users.length})');
    return Response.ok(
      jsonEncode({'success': true, 'users': users}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('❌ Error en /admin/users: $e');
    print(st);
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
