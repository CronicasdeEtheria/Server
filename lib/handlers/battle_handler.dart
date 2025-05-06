import 'dart:convert';
import 'dart:math';
import 'package:guildserver/db/db.dart';
import 'package:guildserver/services/battle_services.dart';
import 'package:shelf/shelf.dart';

final _rng = Random();

Future<Response> randomBattleHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final uid = data['uid'];
    final armySent = Map<String, int>.from(data['army']);

    if (uid == null || armySent.isEmpty) {
      return Response(400, body: 'Faltan datos.');
    }

    final meRes = await conn.execute(
      'SELECT username, elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    if (meRes.rows.isEmpty) return Response(404, body: 'Jugador no encontrado.');
    final myUsername = meRes.rows.first.colAt(0);
    final myElo = int.parse(meRes.rows.first.colAt(1) ?? '1000');

    // Verificar ejército disponible
    final armyRes = await conn.execute(
      'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
      {'uid': uid},
    );
    final myFullArmy = {
      for (final row in armyRes.rows)
        row.colAt(0)!: int.parse(row.colAt(1) ?? '0')
    };

    for (final e in armySent.entries) {
      if (!myFullArmy.containsKey(e.key) || myFullArmy[e.key]! < e.value) {
        return Response(400, body: 'No tenés suficientes unidades de ${e.key}.');
      }
    }

    // Buscar oponente
    final List<Map<String, dynamic>> candidates = [];
    for (int delta = 50; delta <= 500 && candidates.isEmpty; delta += 50) {
      final oppRes = await conn.execute('''
        SELECT u.id, u.username, u.elo
        FROM users u
        JOIN army a ON u.id = a.user_id
        WHERE u.id != :uid AND u.elo BETWEEN :min AND :max
        GROUP BY u.id
        HAVING SUM(a.quantity) > 0
        ORDER BY RAND()
        LIMIT 1
      ''', {
        'uid': uid,
        'min': (myElo - delta).toString(),
        'max': (myElo + delta).toString()
      });

      if (oppRes.rows.isNotEmpty) {
        final row = oppRes.rows.first;
        candidates.add({
          'uid': row.colAt(0),
          'username': row.colAt(1),
          'elo': int.parse(row.colAt(2) ?? '1000'),
        });
      }
    }

    if (candidates.isEmpty) {
      return Response(404, body: 'No se encontró oponente.');
    }

    final defender = candidates.first;

    final defArmyRes = await conn.execute(
      'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
      {'uid': defender['uid']},
    );

    final defArmy = {
      for (final row in defArmyRes.rows)
        row.colAt(0)!: int.parse(row.colAt(1) ?? '0')
    };

    // Simular batalla
    final sim = simulateBattle(armySent, defArmy);

    // Calcular bajas
    Map<String, int> calcLoss(Map<String, int> original, Map<String, int> survivors) =>
        original.map((k, v) => MapEntry(k, v - (survivors[k] ?? 0)));

    final lossesAtt = calcLoss(armySent, sim.survivorsAttacker);
    final lossesDef = calcLoss(defArmy, sim.survivorsDefender);

    // Actualizar ejércitos
    for (final entry in sim.survivorsAttacker.entries) {
      await conn.execute(
        'UPDATE army SET quantity = :q WHERE user_id = :uid AND unit_type = :type',
        {'q': entry.value.toString(), 'uid': uid, 'type': entry.key},
      );
    }
    for (final entry in sim.survivorsDefender.entries) {
      await conn.execute(
        'UPDATE army SET quantity = :q WHERE user_id = :uid AND unit_type = :type',
        {
          'q': entry.value.toString(),
          'uid': defender['uid'],
          'type': entry.key,
        },
      );
    }

    // Elo y recompensas
    final winner = sim.attackerWon ? 'attacker' : 'defender';
    final sA = sim.attackerWon ? 1 : 0;
    final eA = 1 / (1 + pow(10, (defender['elo'] - myElo) / 400));
    final newElo = (myElo + 32 * (sA - eA)).round();
    final eloDelta = newElo - myElo;

    await conn.execute(
      'UPDATE users SET elo = :elo WHERE id = :uid',
      {'elo': newElo.toString(), 'uid': uid},
    );

    if (sim.attackerWon) {
      await conn.execute(
        'UPDATE resources SET gold = gold + :g WHERE user_id = :uid',
        {'g': sim.goldReward.toString(), 'uid': uid},
      );
    }

    return Response.ok(jsonEncode({
      'attacker': {
        'uid': uid,
        'username': myUsername,
        'units_used': armySent,
      },
      'defender': {
        'uid': defender['uid'],
        'username': defender['username'],
        'units_used': defArmy,
      },
      'winner': winner,
      'elo_delta': eloDelta,
      'gold_reward': sim.attackerWon ? sim.goldReward : 0,
      'losses_attacker': lossesAtt,
      'losses_defender': lossesDef,
    }));
  } catch (e) {
    return Response(500, body: 'Error al realizar batalla: $e');
  }
}
