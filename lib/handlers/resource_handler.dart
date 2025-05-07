// lib/handlers/collect_resources_handler.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';

Future<Response> collectResourcesHandler(Request request) async {
  final data = jsonDecode(await request.readAsString()) as Map<String,dynamic>;
  final uid  = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final conn = await getConnection();

    final res = await conn.execute(
      '''
      SELECT  r.food, r.wood, r.stone, r.last_updated,
              b.farm_level, b.lumbermill_level, b.stonemine_level, b.warehouse_level
      FROM    resources r
      JOIN    buildings b ON r.user_id = b.user_id
      WHERE   r.user_id = :uid
      ''',
      {'uid': uid},
    );

    if (res.rows.isEmpty) return Response(404, body:'Usuario no encontrado.');

    final row   = res.rows.first.assoc();
    int foodCur = int.parse(row['food'] ?? '0');
    int woodCur = int.parse(row['wood'] ?? '0');
    int stoneCur= int.parse(row['stone']?? '0');

    final last  = DateTime.parse(row['last_updated']!);
    final secs  = DateTime.now().difference(last).inSeconds;

    final farmLv   = int.parse(row['farm_level']     ?? '0');
    final lumberLv = int.parse(row['lumbermill_level']??'0');
    final mineLv   = int.parse(row['stonemine_level'] ??'0');
    final wareLv   = int.parse(row['warehouse_level'] ??'0');

    const rate = 50;                       // 50 por nivel y hora
    int pending(int level) => (secs / 3600 * rate * level).floor();

    final addFood  = _cap(pending(farmLv),   foodCur,  wareLv);
    final addWood  = _cap(pending(lumberLv), woodCur,  wareLv);
    final addStone = _cap(pending(mineLv),   stoneCur, wareLv);

    await conn.execute(
      '''
      UPDATE resources SET
        food  = food  + :f,
        wood  = wood  + :w,
        stone = stone + :s,
        last_updated = :now
      WHERE user_id = :uid
      ''',
      {
        'f'  : addFood,
        'w'  : addWood,
        's'  : addStone,
        'now': DateTime.now().toIso8601String(),
        'uid': uid,
      },
    );

    return Response.ok(jsonEncode({
      'ok': true,
      'collected': {'food':addFood,'wood':addWood,'stone':addStone},
      'max_capacity': wareLv * 500,
    }));
  } catch (e) {
    return Response.internalServerError(body:'Error al recolectar: $e');
  }
}

// ‑‑‑ Helpers ‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑
int _cap(int toAdd, int current, int wareLv) {
  final cap = wareLv * 500;
  final space = cap - current;
  return toAdd > space ? space.clamp(0, cap) : toAdd;
}
