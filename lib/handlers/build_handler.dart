import 'dart:convert';
import 'package:guildserver/catalog/building_catalog.dart';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';

Map<String, dynamic> calculateUpgradeCost(String buildingId, int currentLevel) {
  final b = buildingCatalog[buildingId];
  if (b == null) throw Exception('Edificio no válido');

  final factor = 1 + (currentLevel * 0.3);
  return {
    'duration_seconds': (b.baseTime * factor).round(),
    'wood': (b.baseCostWood * factor).round(),
    'stone': (b.baseCostStone * factor).round(),
    'food': (b.baseCostFood * factor).round(),
  };
}
Future<Response> startConstruction(Request request) async {
  try {
    final conn = await getConnection();

    // ──────────────────── UID desde cabecera ────────────────────
    final uid = request.headers['uid'];
    if (uid == null || uid.isEmpty) {
      return Response.forbidden('Token inválido.');
    }

    // ──────────────────── Body JSON ─────────────────────────────
    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final buildingId  = data['buildId']      as String?;   // ← nombre igual al cliente
    final targetLevel = data['targetLevel']  as int?;      // opcional

    if (buildingId == null) {
      return Response(400, body: 'Falta buildId.');
    }

    final building = buildingCatalog[buildingId];
    if (building == null) {
      return Response(400, body: 'Edificio inválido.');
    }

    // ─────── nivel actual y ayuntamiento ───────
    final lvRes = await conn.execute('''
      SELECT ${buildingId}_level AS lv, townhall_level
      FROM buildings
      WHERE user_id = :uid
    ''', {'uid': uid});

    if (lvRes.rows.isEmpty) {
      return Response(404, body: 'Usuario sin registro de edificios.');
    }

    final row           = lvRes.rows.first.assoc();
    final currentLevel  = int.parse(row['lv']!);
    final townhallLevel = int.parse(row['townhall_level']!);

    // nivel que se quiere alcanzar
    final nextLevel = targetLevel ?? (currentLevel + 1);

    if (nextLevel > building.maxLevel) {
      return Response(400, body: 'Excede nivel máximo (${building.maxLevel}).');
    }
    // …después de calcular nextLevel y townhallLevel

if (buildingId != 'townhall' && nextLevel > 3 && nextLevel > townhallLevel) {
  return Response(
    400,
    body: 'Primero sube el ayuntamiento a Lv $nextLevel.',
  );
}


    // ─────── calcular coste / duración ───────
    final cost = calculateUpgradeCost(buildingId, currentLevel);

    // ─────── comprobar recursos ───────
    final res = await conn.execute(
      'SELECT food, wood, stone FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );
    final r = res.rows.first.assoc();
    if (int.parse(r['food']!)  < cost['food']  ||
        int.parse(r['wood']!)  < cost['wood']  ||
        int.parse(r['stone']!) < cost['stone']) {
      return Response(400, body: 'Recursos insuficientes.');
    }

    // ─────── descontar recursos ───────
    await conn.execute('''
      UPDATE resources SET
        food  = food  - :food,
        wood  = wood  - :wood,
        stone = stone - :stone
      WHERE user_id = :uid
    ''', {
      'food' : cost['food'],
      'wood' : cost['wood'],
      'stone': cost['stone'],
      'uid'  : uid,
    });

    // ─────── encolar construcción ───────
    await conn.execute('''
      INSERT INTO construction_queue
        (user_id, building_id, target_level, duration_seconds, started_at)
      VALUES (:uid, :bid, :tLv, :dur, NOW())
    ''', {
      'uid': uid,
      'bid': buildingId,
      'tLv': nextLevel,
      'dur': cost['duration_seconds'],
    });

    return Response.ok(
      jsonEncode({
        'ok': true,
        'queued': {
          'building': buildingId,
          'targetLevel': nextLevel,
          'cost': cost,
        }
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
        body: 'Error al iniciar construcción: $e');
  }
}

Future<Response> cancelConstruction(Request request) async {
  try {
    final conn = await getConnection();
    final uid = request.headers['uid'];
    if (uid == null || uid.isEmpty) return Response.forbidden('Token inválido.');

    // primera obra en cola (o puedes pedir building_id opcional en el body)
    final qRes = await conn.execute(
      '''
      SELECT id, building_id, target_level, food, wood, stone
      FROM   construction_queue
      WHERE  user_id = :uid
      ORDER  BY started_at
      LIMIT  1
      ''',
      {'uid': uid},
    );
    if (qRes.rows.isEmpty) {
      return Response(400, body: 'No hay construcción en progreso.');
    }

    final q = qRes.rows.first.assoc();

    // reembolso 50 %
    int half(String k) => (int.parse(q[k]!) / 2).round();
    await conn.execute(
      '''
      UPDATE resources SET
        food  = food  + :f,
        wood  = wood  + :w,
        stone = stone + :s
      WHERE user_id = :uid
      ''',
      {
        'f': half('food'),
        'w': half('wood'),
        's': half('stone'),
        'uid': uid,
      });

    await conn.execute('DELETE FROM construction_queue WHERE id = :id',
        {'id': q['id']});

    return Response.ok(jsonEncode({
      'ok': true,
      'cancelled': q['building_id'],
      'refunded': {
        'food': half('food'),
        'wood': half('wood'),
        'stone': half('stone')
      }
    }));
  } catch (e) {
    return Response.internalServerError(body: 'Cancel error: $e');
  }
}

Future<Response> checkConstructionStatus(Request request) async {
  try {
    final conn = await getConnection();
    final uid = request.headers['uid'];
    if (uid == null || uid.isEmpty) {
      return Response.forbidden('Token inválido.');
    }

    // Obtenemos todas las obras en cola
    final qRes = await conn.execute('''
      SELECT id, building_id, target_level, duration_seconds, started_at
      FROM   construction_queue
      WHERE  user_id = :uid
      ORDER BY started_at ASC
    ''', {'uid': uid});

    final now = DateTime.now();
    final List<Map<String, dynamic>> queueItems = [];

    // Cambio aquí: id es String
    String? firstCompletedId;
    String? firstCompletedBuilding;
    int? firstCompletedLevel;

    for (final row in qRes.rows) {
      final m = row.assoc();
      final id       = m['id']!;                // String
      final building = m['building_id']!;       // String
      final target   = int.parse(m['target_level']!);
      final dur      = int.parse(m['duration_seconds']!);
      final started  = DateTime.parse(m['started_at']!);
      final finishAt = started.add(Duration(seconds: dur));

      if (now.isAfter(finishAt)) {
        // Marcamos la primera completada
        if (firstCompletedId == null) {
          firstCompletedId        = id;
          firstCompletedBuilding  = building;
          firstCompletedLevel     = target;
        }
      } else {
        final remaining = finishAt.difference(now).inSeconds;
        queueItems.add({
          'building': building,
          'target': target,
          'remaining': remaining,
        });
      }
    }

    Map<String, dynamic>? completed;
    if (firstCompletedId != null) {
      // Borrar de la cola
      await conn.execute(
        'DELETE FROM construction_queue WHERE id = :id',
        {'id': firstCompletedId},
      );
      // Actualizar nivel
      await conn.execute('''
        UPDATE buildings
           SET ${firstCompletedBuilding}_level = :newLv
         WHERE user_id = :uid
      ''', {
        'newLv': firstCompletedLevel,
        'uid': uid,
      });

      completed = {
        'building': firstCompletedBuilding,
        'level': firstCompletedLevel,
      };
    }

    return Response.ok(
      jsonEncode({
        'ok': true,
        'status': completed != null
            ? 'completed'
            : (queueItems.isEmpty ? 'idle' : 'building'),
        if (completed != null) 'completed': completed,
        'queue': queueItems,
        'max': 2,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(body: 'Status error: $e');
  }
}