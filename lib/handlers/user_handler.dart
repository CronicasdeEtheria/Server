import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Future<Response> getUserProfile(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();

    // — Usuario —
    final userRes = await pool.execute(
      'SELECT username, race, elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    if (userRes.rows.isEmpty) {
      return Response(404, body: 'Usuario no encontrado.');
    }
    final u = userRes.rows.first.assoc();
    final username = u['username']!;
    final race     = u['race']!;
    final elo      = int.parse(u['elo']!);

    // — Recursos —
    final resRes = await pool.execute(
      'SELECT food, wood, stone, gold FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );
    final r = resRes.rows.first.assoc();
    final food  = int.parse(r['food']!);
    final wood  = int.parse(r['wood']!);
    final stone = int.parse(r['stone']!);
    final gold  = int.parse(r['gold']!);

    // — Edificios —
    final bldRes = await pool.execute(
      '''
      SELECT
        barracks_level,
        warehouse_level,
        farm_level,
        lumbermill_level,
        townhall_level,
        stone_mine_level,
        gold_mine_level
      FROM buildings
      WHERE user_id = :uid
      ''',
      {'uid': uid},
    );
    final b = bldRes.rows.first.assoc();
    final barracks     = int.parse(b['barracks_level']!);
    final warehouse    = int.parse(b['warehouse_level']!);
    final farm         = int.parse(b['farm_level']!);
    final lumbermill   = int.parse(b['lumbermill_level']!);
    final townhall     = int.parse(b['townhall_level']!);
    final stoneMine    = int.parse(b['stone_mine_level']!);
    final goldMine     = int.parse(b['gold_mine_level']!);

    // — Ejército —
    final armyRes = await pool.execute(
      'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
      {'uid': uid},
    );
    final army = <String, int>{};
    for (final row in armyRes.rows) {
      final a = row.assoc();
      army[a['unit_type']!] = int.parse(a['quantity']!);
    }

    // — Respuesta —
    final response = {
      'username': username,
      'race': race,
      'elo': elo,
      'resources': {
        'food': food,
        'wood': wood,
        'stone': stone,
        'gold': gold,
      },
      'buildings': {
        'barracks': barracks,
        'warehouse': warehouse,
        'farm': farm,
        'lumbermill': lumbermill,
        'townhall': townhall,
        'stone_mine': stoneMine,
        'gold_mine': goldMine,
      },
      'army': army,
    };

    return Response.ok(jsonEncode(response));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener datos del usuario: $e',
    );
  }
}
