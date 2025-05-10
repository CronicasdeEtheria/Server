import 'dart:convert';
import 'dart:math';
import 'package:guildserver/db/db.dart';
import 'package:guildserver/services/battle_services.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();


Future<Response> randomBattleHandler(Request request) async {
  final rawBody = await request.readAsString();
  print('🔔 /battle/random body: $rawBody');
  try {
    final conn = await getConnection();
    final data = jsonDecode(rawBody) as Map<String, dynamic>;
    final uid = data['uid']?.toString();
    final armySent = Map<String, int>.from(data['army'] as Map);
    if (uid == null || armySent.isEmpty) {
      return Response(400, body: 'Faltan datos.');
    }
    final meRes = await conn.execute(
      'SELECT username, elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    if (meRes.rows.isEmpty) {
      return Response(404, body: 'Jugador no encontrado.');
    }
    final myUsername = meRes.rows.first.colAt(0)!;
    final myElo = int.parse(meRes.rows.first.colAt(1) ?? '1000');
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
        return Response(400, body: 'No tenés suficientes unidades de \${e.key}.');
      }
    }
    Map<String, dynamic>? defender;
    for (int delta = 50; delta <= 500 && defender == null; delta += 50) {
      final oppRes = await conn.execute('''
        SELECT u.id, u.username, u.elo
          FROM users u
          JOIN army a ON u.id = a.user_id
         WHERE u.id != :uid
           AND u.elo BETWEEN :min AND :max
         GROUP BY u.id
        HAVING SUM(a.quantity) > 0
         ORDER BY RAND()
         LIMIT 1
      ''', {
        'uid': uid,
        'min': (myElo - delta).toString(),
        'max': (myElo + delta).toString(),
      });
      if (oppRes.rows.isNotEmpty) {
        final row = oppRes.rows.first;
        defender = {
          'uid': row.colAt(0)!,
          'username': row.colAt(1)!,
          'elo': int.parse(row.colAt(2) ?? '1000'),
        };
      }
    }
    if (defender == null) {
      return Response(404, body: 'No se encontró oponente.');
    }
    final defArmyRes = await conn.execute(
      'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
      {'uid': defender['uid']},
    );
    final defArmy = {
      for (final row in defArmyRes.rows)
        row.colAt(0)!: int.parse(row.colAt(1) ?? '0')
    };
    final sim = simulateBattle(armySent, defArmy);
    Map<String, int> calcLoss(Map<String, int> original, Map<String, int> survivors) =>
        original.map((k, v) => MapEntry(k, v - (survivors[k] ?? 0)));
    final lossesAtt = calcLoss(armySent, sim.survivorsAttacker);
    final lossesDef = calcLoss(defArmy, sim.survivorsDefender);
    for (var entry in sim.survivorsAttacker.entries) {
      await conn.execute(
        'UPDATE army SET quantity = :q WHERE user_id = :uid AND unit_type = :type',
        {'q': entry.value.toString(), 'uid': uid, 'type': entry.key},
      );
    }
    for (var entry in sim.survivorsDefender.entries) {
      await conn.execute(
        'UPDATE army SET quantity = :q WHERE user_id = :uid AND unit_type = :type',
        {'q': entry.value.toString(), 'uid': defender['uid'], 'type': entry.key},
      );
    }
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
    final reportId = _uuid.v4();
    try {
      await conn.execute(
        '''
        INSERT INTO battle_reports (
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
        ) VALUES (
          :id, :attId, :defId, :attUser, :defUser,
          :winner, :gold, :eloDelta,
          :attArmy, :defArmy,
          :lossAtt, :lossDef,
          NOW()
        )
        ''',
        {
          'id': reportId,
          'attId': uid,
          'defId': defender['uid'],
          'attUser': myUsername,
          'defUser': defender['username'],
          'winner': winner,
          'gold': sim.goldReward.toString(),
          'eloDelta': eloDelta.toString(),
          'attArmy': jsonEncode(armySent),
          'defArmy': jsonEncode(defArmy),
          'lossAtt': jsonEncode(lossesAtt),
          'lossDef': jsonEncode(lossesDef),
        },
      );
      print('✅ Report inserted: $reportId');
    } catch (e, st) {
      print('❌ Failed to insert report: $e\n$st');
    }
    return Response.ok(jsonEncode({
      'attacker': {'uid': uid, 'username': myUsername, 'units_used': armySent},
      'defender': {'uid': defender['uid'], 'username': defender['username'], 'units_used': defArmy},
      'winner': winner,
      'elo_delta': eloDelta,
      'gold_reward': sim.attackerWon ? sim.goldReward : 0,
      'losses_attacker': lossesAtt,
      'losses_defender': lossesDef,
    }));
  } catch (e, st) {
    print('❌ randomBattleHandler error: $e\n$st');
    return Response(500, body: 'Error al realizar batalla: $e');
  }
}

Future<Response> battleArmyHandler(Request request) async {
  final raw = await request.readAsString();
  print('🔔 /battle/army body: $raw');
  final pool = await getConnection();
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final uid = data['uid']?.toString();
  if (uid == null) {
    return Response(400,
      body: jsonEncode({'error': 'Falta uid'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
  final res = await pool.execute(
    'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
    {'uid': uid},
  );
  final list = res.rows.map((r) {
    final m = r.assoc();
    return {'unit_type': m['unit_type'], 'quantity': int.parse(m['quantity']!)};
  }).toList();
  return Response.ok(
    jsonEncode(list),
    headers: {'Content-Type':'application/json'},
  );
}

