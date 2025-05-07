// lib/handlers/users_stats_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';

Future<Response> getUserStatsHandler(Request request) async {
  final uid = request.headers['uid'];
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta uid en cabecera.');
  }

  try {
    final conn = await getConnection();

    // ── Recursos ───────────────────────────────────────
    final resRows = await conn.execute(
      'SELECT food, wood, stone, gold FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );

    var resources = {'food': 0, 'wood': 0, 'stone': 0, 'gold': 0};
    if (resRows.rows.isNotEmpty) {
      final r = resRows.rows.first.assoc();
      resources = {
        'food' : int.parse(r['food']  ?? '0'),
        'wood' : int.parse(r['wood']  ?? '0'),
        'stone': int.parse(r['stone'] ?? '0'),
        'gold' : int.parse(r['gold']  ?? '0'),
      };
    }

    // ── Niveles de edificios ────────────────────────────
    final bRows = await conn.execute('''
      SELECT
        farm_level,
        lumbermill_level,
        stone_mine_level,
        warehouse_level,
        townhall_level,
        barracks_level
      FROM buildings
      WHERE user_id = :uid
    ''', {'uid': uid});

    int farmLv      = 1;
    int lumberLv    = 1;
    int mineLv      = 1;
    int wareLv      = 1;
    int hallLv      = 1;
    int barracksLv  = 1;

    final buildings = <Map<String, dynamic>>[];

    if (bRows.rows.isNotEmpty) {
      final b = bRows.rows.first.assoc();
      farmLv     = int.parse(b['farm_level']       ?? '1');
      lumberLv   = int.parse(b['lumbermill_level'] ?? '1');
      mineLv     = int.parse(b['stone_mine_level'] ?? '1');
      wareLv     = int.parse(b['warehouse_level']  ?? '1');
      hallLv     = int.parse(b['townhall_level']   ?? '1');
      barracksLv = int.parse(b['barracks_level']   ?? '1');
    }

    buildings.addAll([
      {'id': 'farm',       'level': farmLv},
      {'id': 'lumbermill', 'level': lumberLv},
      {'id': 'stonemine',  'level': mineLv},
      {'id': 'warehouse',  'level': wareLv},
      {'id': 'townhall',   'level': hallLv},
      {'id': 'barracks',   'level': barracksLv},
      // Coliseo siempre nivel 1
      {'id': 'coliseo',    'level': 1},
    ]);

    // ── Producción y capacidad ───────────────────────────
    final prodHour = {
      'food' : farmLv   * 50,
      'wood' : lumberLv * 50,
      'stone': mineLv   * 50,
      'gold' : 0,
    };

    final capacity = {
      'food' : wareLv * 500,
      'wood' : wareLv * 500,
      'stone': wareLv * 500,
      'gold' : wareLv * 500,
    };

    return Response.ok(
      jsonEncode({
        'ok'        : true,
        'resources' : resources,
        'prod_hour' : prodHour,
        'capacity'  : capacity,
        'buildings' : buildings,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('stats error → $e\n$st');
    return Response.internalServerError(body: 'stats error');
  }
}
