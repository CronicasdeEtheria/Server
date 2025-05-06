import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Future<Response> getUserBattleStatsHandler(Request request) async {
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
        attacker_id,
        defender_id,
        winner,
        gold_reward,
        losses_attacker,
        losses_defender
      FROM battle_reports
      WHERE attacker_id = :uid OR defender_id = :uid
      ''',
      {'uid': uid},
    );

    int wins = 0;
    int losses = 0;
    int winsAsAttacker = 0;
    int winsAsDefender = 0;
    int totalGold = 0;
    int totalLosses = 0;

    for (final row in result.rows) {
      final r = row.assoc();
      final attackerId    = r['attacker_id']!;
      final defenderId    = r['defender_id']!;
      final winner        = r['winner']!;
      final goldReward    = int.parse(r['gold_reward']!);
      final lossesAttStr  = r['losses_attacker']!;
      final lossesDefStr  = r['losses_defender']!;

      final isAttacker = attackerId == uid;
      final isDefender = defenderId == uid;

      if ((isAttacker && winner == 'attacker') ||
          (isDefender && winner == 'defender')) {
        wins++;
        if (isAttacker) winsAsAttacker++;
        if (isDefender) winsAsDefender++;
        if (isAttacker) totalGold += goldReward;
      } else {
        losses++;
      }

      final lossMap = jsonDecode(
          isAttacker ? lossesAttStr : lossesDefStr
      ) as Map<String, dynamic>;
      totalLosses += lossMap.values.fold<int>(0, (sum, v) => sum + (v as int));
    }

    return Response.ok(jsonEncode({
      'wins': wins,
      'losses': losses,
      'wins_as_attacker': winsAsAttacker,
      'wins_as_defender': winsAsDefender,
      'gold_earned': totalGold,
      'troops_lost': totalLosses,
    }));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener estadísticas de batalla: $e',
    );
  }
}
