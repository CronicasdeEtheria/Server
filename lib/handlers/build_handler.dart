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

    final data = jsonDecode(await request.readAsString());
    final uid = data['uid'];
    final buildingId = data['building_id'];

    if (uid == null || buildingId == null) {
      return Response(400, body: 'Faltan parámetros.');
    }

    final building = buildingCatalog[buildingId];
    if (building == null) return Response(400, body: 'Edificio inválido.');

    final levelsRes = await conn.execute('''
      SELECT ${buildingId}_level, townhall_level FROM buildings WHERE user_id = :uid
    ''', {'uid': uid});
    final row = levelsRes.rows.first;
    final currentLevel = int.parse(row.colAt(0) ?? '0');
    final townhallLevel = int.parse(row.colAt(1) ?? '0');

    if (currentLevel >= building.maxLevel) {
      return Response(400, body: 'Edificio ya está al nivel máximo.');
    }

    if (buildingId != 'townhall' && currentLevel >= townhallLevel) {
      return Response(400, body: 'Debes subir el ayuntamiento primero.');
    }

    final cost = calculateUpgradeCost(buildingId, currentLevel);

    final res = await conn.execute(
      'SELECT food, wood, stone FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );
    final resRow = res.rows.first;

    if (int.parse(resRow.colAt(0)!) < cost['food'] ||
        int.parse(resRow.colAt(1)!) < cost['wood'] ||
        int.parse(resRow.colAt(2)!) < cost['stone']) {
      return Response(400, body: 'Recursos insuficientes.');
    }

    await conn.execute('''
      UPDATE resources SET 
        food = food - :food, 
        wood = wood - :wood, 
        stone = stone - :stone 
      WHERE user_id = :uid
    ''', {
      'food': cost['food'].toString(),
      'wood': cost['wood'].toString(),
      'stone': cost['stone'].toString(),
      'uid': uid,
    });

    await conn.execute('''
      INSERT INTO construction_queue (user_id, building_id, duration_seconds)
      VALUES (:uid, :bid, :duration)
    ''', {
      'uid': uid,
      'bid': buildingId,
      'duration': cost['duration_seconds'].toString(),
    });

    return Response.ok(jsonEncode({'status': 'queued', 'cost': cost}));
  } catch (e) {
    return Response(500, body: 'Error al iniciar construcción: $e');
  }
}

Future<Response> cancelConstruction(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final uid = data['uid'];
    if (uid == null) return Response(400, body: 'Falta el uid.');

    final qRes = await conn.execute(
      'SELECT id, building_id FROM construction_queue WHERE user_id = :uid LIMIT 1',
      {'uid': uid},
    );
    if (qRes.rows.isEmpty) {
      return Response(400, body: 'No hay construcción en progreso.');
    }

    final row = qRes.rows.first;
    final refund = {'food': 50, 'wood': 50, 'stone': 50};

    await conn.execute('''
      UPDATE resources SET 
        food = food + :food, 
        wood = wood + :wood, 
        stone = stone + :stone
      WHERE user_id = :uid
    ''', {
      'food': refund['food'].toString(),
      'wood': refund['wood'].toString(),
      'stone': refund['stone'].toString(),
      'uid': uid,
    });

    await conn.execute(
      'DELETE FROM construction_queue WHERE id = :id',
      {'id': row.colAt(0)},
    );

    return Response.ok(jsonEncode({'status': 'cancelled', 'refunded': refund}));
  } catch (e) {
    return Response(500, body: 'Error al cancelar construcción: $e');
  }
}

Future<Response> checkConstructionStatus(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final uid = data['uid'];
    if (uid == null) return Response(400, body: 'Falta el uid.');

    final qRes = await conn.execute(
      'SELECT id, building_id, started_at, duration_seconds FROM construction_queue WHERE user_id = :uid',
      {'uid': uid},
    );

    if (qRes.rows.isEmpty) {
      return Response.ok(jsonEncode({'status': 'idle'}));
    }

    final row = qRes.rows.first;
    final startedAt = DateTime.parse(row.colAt(2)!);
    final duration = int.parse(row.colAt(3)!);
    final finishTime = startedAt.add(Duration(seconds: duration));
    final now = DateTime.now();

    if (now.isAfter(finishTime)) {
      await conn.execute(
        'DELETE FROM construction_queue WHERE id = :id',
        {'id': row.colAt(0)},
      );

      await conn.execute(
        'UPDATE buildings SET ${row.colAt(1)}_level = ${row.colAt(1)}_level + 1 WHERE user_id = :uid',
        {'uid': uid},
      );

      return Response.ok(jsonEncode({
        'status': 'completed',
        'building_id': row.colAt(1),
      }));
    }

    return Response.ok(jsonEncode({
      'status': 'building',
      'building_id': row.colAt(1),
      'remaining_seconds': finishTime.difference(now).inSeconds
    }));
  } catch (e) {
    return Response(500, body: 'Error al revisar construcción: $e');
  }
}
