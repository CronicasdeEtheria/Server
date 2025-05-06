import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Future<Response> getUserStatsHandler(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();
    final result = await pool.execute(
      '''
      SELECT
        total_food,
        total_wood,
        total_stone,
        last_updated
      FROM resource_stats
      WHERE user_id = :uid
      ''',
      {'uid': uid},
    );

    if (result.rows.isEmpty) {
      return Response(404, body: 'Estadísticas no encontradas.');
    }

    final row = result.rows.first.assoc();
    final food        = int.parse(row['total_food']!);
    final wood        = int.parse(row['total_wood']!);
    final stone       = int.parse(row['total_stone']!);
    final lastUpdated = DateTime.parse(row['last_updated']!).toIso8601String();

    return Response.ok(jsonEncode({
      'food': food,
      'wood': wood,
      'stone': stone,
      'last_updated': lastUpdated,
    }));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener estadísticas: $e',
    );
  }
}
