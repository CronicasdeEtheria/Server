import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';
Future<Response> rankingHandler(Request request) async {
  final params = request.url.queryParameters;
  final type = params['type'] ?? 'elo';
  final raceFilter = params['race'];
  final limit = int.tryParse(params['limit'] ?? '20') ?? 20;

  try {
    final pool = await getConnection();
    List<Map<String, dynamic>> data;

    if (type == 'elo') {
      final sql = '''
        SELECT username, race, elo
          FROM users
        ${raceFilter != null ? 'WHERE race = :race' : ''}
        ORDER BY elo DESC
        LIMIT :limit
      ''';
      final args = <String, dynamic>{ 'limit': limit };
      if (raceFilter != null) args['race'] = raceFilter;

      final result = await pool.execute(sql, args);
      data = result.rows.map((row) {
        final r = row.assoc();
        return {
          'username': r['username']!,
          'race': r['race']!,
          'elo': int.parse(r['elo']!),
        };
      }).toList();

      return Response.ok(jsonEncode(data));
    }

    if (type == 'production') {
      final sql = '''
        SELECT u.username, u.race,
               (rs.total_food + rs.total_wood + rs.total_stone) AS produced_total
          FROM users u
          JOIN resource_stats rs ON u.id = rs.user_id
         ORDER BY produced_total DESC
         LIMIT :limit
      ''';
      final result = await pool.execute(sql, {'limit': limit});
      data = result.rows.map((row) {
        final r = row.assoc();
        return {
          'username': r['username']!,
          'race': r['race']!,
          'produced_total': int.parse(r['produced_total']!),
        };
      }).toList();

      return Response.ok(jsonEncode(data));
    }

    if (type == 'victories') {
      final sql = '''
        SELECT u.username, u.race,
               COUNT(*) AS wins
          FROM battle_reports br
          JOIN users u
            ON (br.attacker_id = u.id AND br.winner = 'attacker')
           OR (br.defender_id = u.id AND br.winner = 'defender')
         GROUP BY u.username, u.race
         ORDER BY wins DESC
         LIMIT :limit
      ''';
      final result = await pool.execute(sql, {'limit': limit});
      data = result.rows.map((row) {
        final r = row.assoc();
        return {
          'username': r['username']!,
          'race': r['race']!,
          'wins': int.parse(r['wins']!),
        };
      }).toList();

      return Response.ok(jsonEncode(data));
    }

    return Response(400, body: 'Tipo de ranking inválido.');
  } catch (e) {
    return Response.internalServerError(body: 'Error al obtener ranking: $e');
  }
}
