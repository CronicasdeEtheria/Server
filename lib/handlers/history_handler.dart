import 'dart:convert';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';


Future<Response> battleHistoryHandler(Request request) async {
  // Leer payload
  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    // Obtener pool de conexiones
    final pool = await getConnection();

    // Ejecutar consulta
    final result = await pool.execute(
      '''
      SELECT
        id,
        attacker_id,
        defender_id,
        attacker_username,
        defender_username,
        winner,
        gold_reward,
        elo_delta,
        attacker_army,
        defender_army,
        losses_attacker,
        losses_defender,
        battle_time
      FROM battle_reports
      WHERE attacker_id = :uid OR defender_id = :uid
      ORDER BY battle_time DESC
      LIMIT 20
      ''',
      {'uid': uid},
    );

    // Mapear resultado
    final history = result.rows.map((row) {
      final r = row.assoc();
      final isAttacker = r['attacker_id'] == uid;
      final armyJson = r[isAttacker ? 'attacker_army' : 'defender_army']!;
      final lossesJson = r[isAttacker ? 'losses_attacker' : 'losses_defender']!;

      final winner = r['winner']!;
      final goldReward = int.parse(r['gold_reward']!);
      final eloDelta = int.parse(r['elo_delta']!);
      final battleTime = DateTime.parse(r['battle_time']!).toUtc().toIso8601String();

      return {
        'date': battleTime,
        'as': isAttacker ? 'attacker' : 'defender',
        'opponent': r[isAttacker ? 'defender_username' : 'attacker_username']!,
        'winner': winner,
        'elo_delta': eloDelta,
        'gold_reward': (isAttacker && winner == 'attacker') ? goldReward : 0,
        'army_used': jsonDecode(armyJson),
        'army_lost': jsonDecode(lossesJson),
      };
    }).toList();

    return Response.ok(jsonEncode(history));
  } catch (e) {
    return Response.internalServerError(body: 'Error al obtener historial: $e');
  }
}
