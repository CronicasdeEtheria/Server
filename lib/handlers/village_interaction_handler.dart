import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import '../db/db.dart';

Future<Response> spyHandler(Request req, String villageId) async {
  final conn = await getConnection();
  final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  final playerId = data['player_id'] as String?;
  if (playerId == null) {
    return Response(400, body: 'player_id requerido');
  }
  final res = await conn.execute(
    '''
    SELECT r.food, r.wood, r.stone, r.gold, r.last_updated
      FROM resources r
      JOIN villages v ON v.player_id = r.user_id
     WHERE v.id = ?
    ''',
    [int.parse(villageId)] as Map<String, dynamic>?
  );
  if (res.rows.isEmpty) {
    return Response(404, body: 'Aldea no encontrada');
  }
  final r0 = res.rows.first;
  final spyInfo = {
    'food': r0.colAt(0),
    'wood': r0.colAt(1),
    'stone': r0.colAt(2),
    'gold': r0.colAt(3),
    'last_seen': (r0.colAt(4) as DateTime).toIso8601String(),
  };
  return Response.ok(jsonEncode(spyInfo), headers: {'Content-Type': 'application/json'});
}

Future<Response> attackHandler(Request req, String villageId) async {
  final conn = await getConnection();
  final data = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  final playerId = data['player_id'] as String?;
  final army = data['army'] as Map<String, dynamic>?;
  if (playerId == null || army == null) {
    return Response(400, body: 'player_id y army requeridos');
  }
  final battleId = const Uuid().v4();
  await conn.execute(
    '''
    INSERT INTO battles (id, attacker_id, defender_village_id, army_json, created_at)
    VALUES (:id, :attacker, :defender, :army, NOW())
    ''',
    {
      'id': battleId,
      'attacker': playerId,
      'defender': int.parse(villageId),
      'army': jsonEncode(army),
    },
  );
  return Response.ok(jsonEncode({
    'battle_id': battleId,
    'status': 'queued',
  }), headers: {'Content-Type': 'application/json'});
}
