import 'dart:convert';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';

Future<Response> adminRazaStatsHandler(Request request) async {
  try {
    final conn = await getConnection();

    final result = await conn.execute('''
      SELECT race, COUNT(*) as count
      FROM users
      GROUP BY race
    ''');

    final data = result.rows.map((row) {
      final race = row.colByName('race');
      final count = int.parse(row.colByName('count') ?? '0');
      return {'race': race, 'count': count};
    }).toList();

    return Response.ok(
      jsonEncode({'success': true, 'data': data}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'message': 'Error al obtener estadísticas por raza',
        'details': e.toString()
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
