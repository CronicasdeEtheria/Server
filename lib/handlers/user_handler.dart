// lib/handlers/user_handler.dart

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';

/// Ya asume que authMiddleware validó uid+token en headers
Future<Response> getUserProfile(Request request) async {
  final uid = request.headers['uid'];
  if (uid == null || uid.isEmpty) {
    return Response.forbidden('Token inválido.');
  }

  try {
    final conn = await getConnection();

    // — Usuario básico —
    final userRes = await conn.execute(
      'SELECT username, race, elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    if (userRes.rows.isEmpty) {
      return Response.notFound('Usuario no encontrado.');
    }
    final u = userRes.rows.first.assoc();
    final username = u['username']!;
    final race = u['race']!;
    final elo = int.parse(u['elo']!);

    // — Recursos —
    final resRes = await conn.execute(
      'SELECT food, wood, stone, gold FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );
    final r = resRes.rows.first.assoc();
    final food = int.parse(r['food']!);
    final wood = int.parse(r['wood']!);
    final stone = int.parse(r['stone']!);
    final gold = int.parse(r['gold']!);

    // — Edificios —
    final bldRes = await conn.execute(
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
    final barracks = int.parse(b['barracks_level']!);
    final warehouse = int.parse(b['warehouse_level']!);
    final farm = int.parse(b['farm_level']!);
    final lumbermill = int.parse(b['lumbermill_level']!);
    final townhall = int.parse(b['townhall_level']!);
    final stoneMine = int.parse(b['stone_mine_level']!);
    final goldMine = int.parse(b['gold_mine_level']!);

    // — Ejército —
    final armyRes = await conn.execute(
      'SELECT unit_type, quantity FROM army WHERE user_id = :uid',
      {'uid': uid},
    );
    final army = <String, int>{};
    for (final row in armyRes.rows) {
      final a = row.assoc();
      army[a['unit_type']!] = int.parse(a['quantity']!);
    }

    // — Guild membership —
    final gmRes = await conn.execute(
      'SELECT guild_id, is_leader FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    String? guildId;
    bool? isLeader = false;
    if (gmRes.rows.isNotEmpty) {
      final gm = gmRes.rows.first.assoc();
      guildId = gm['guild_id'];
      isLeader = gmRes.rows.first.typedColAt<bool>(1);
    }

    // — Construye la respuesta —
    final response = {
      'ok': true,
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

    if (guildId != null) {
      response['guild_id'] = guildId;
      response['is_leader'] = isLeader!;
    }

    return Response.ok(
      jsonEncode(response),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener datos del usuario: $e',
    );
  }
}
