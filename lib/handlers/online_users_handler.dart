import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';
import '../services/connection_manager.dart';

Future<Response> onlineUsersHandler(Request request) async {
  // 1️⃣ Obtener UIDs conectados
  final uids = connectionManager.connectedUids;
  if (uids.isEmpty) {
    return Response.ok(jsonEncode([]));
  }

  try {
    // 2️⃣ Preparar parámetros nombrados para la consulta
    final placeholders = List.generate(uids.length, (i) => ':id$i').join(', ');
    final params = <String, dynamic>{
      for (var i = 0; i < uids.length; i++) 'id$i': uids[i],
    };

    // 3️⃣ Ejecutar query usando el pool
    final pool = await getConnection();
    final result = await pool.execute(
      '''
      SELECT 
        u.id,
        u.username,
        u.email,
        u.elo,
        u.race,
        g.name AS guild
      FROM users u
      LEFT JOIN guild_members gm ON u.id = gm.user_id
      LEFT JOIN guilds g         ON gm.guild_id = g.id
      WHERE u.id IN ($placeholders)
      ''',
      params,
    );

    // 4️⃣ Mapear filas a JSON
    final users = result.rows.map((row) {
      final r = row.assoc();
      return {
        'uid': r['id']!,
        'username': r['username']!,
        'email': r['email']!,
        'elo': int.parse(r['elo']!),
        'race': r['race']!,
        'guild': r['guild'], // puede ser null
      };
    }).toList();

    return Response.ok(jsonEncode(users));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener usuarios conectados: $e',
    );
  }
}
