import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

final Map<String, int> baseProductionPerHour = {
  'farm': 50,
  'lumbermill': 30,
  'stonemine': 20,
};

Future<Response> collectResourcesHandler(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();
    final res = await pool.execute(
      '''
      SELECT
        r.food,
        r.wood,
        r.stone,
        r.last_updated,
        b.farm_level,
        b.lumbermill_level,
        b.stone_mine_level,
        b.warehouse_level
      FROM resources r
      JOIN buildings b ON r.user_id = b.user_id
      WHERE r.user_id = :uid
      ''',
      {'uid': uid},
    );

    if (res.rows.isEmpty) {
      return Response(404, body: 'Usuario no encontrado.');
    }

    final row = res.rows.first.assoc();
    final currentFood  = int.parse(row['food']!);
    final currentWood  = int.parse(row['wood']!);
    final currentStone = int.parse(row['stone']!);

    final lastUpdated = DateTime.parse(row['last_updated']!);
    final now = DateTime.now();
    final elapsed = now.difference(lastUpdated);

    final farmLevel      = int.parse(row['farm_level']!);
    final lumberLevel    = int.parse(row['lumbermill_level']!);
    final stoneLevel     = int.parse(row['stone_mine_level']!);
    final warehouseLevel = int.parse(row['warehouse_level']!);

    final maxCap = warehouseLevel * 500;

    // Producción pendiente
    int computePending(int base, int level) =>
        (elapsed.inSeconds / 3600 * base * level).floor();

    final pendingFood  = computePending(baseProductionPerHour['farm']!, farmLevel);
    final pendingWood  = computePending(baseProductionPerHour['lumbermill']!, lumberLevel);
    final pendingStone = computePending(baseProductionPerHour['stonemine']!, stoneLevel);

    // Función para no sobrepasar capacidad
    int cap(int current, int add) {
      final total = current + add;
      return (total > maxCap ? maxCap - current : add).clamp(0, maxCap);
    }

    final addFood  = cap(currentFood,  pendingFood);
    final addWood  = cap(currentWood,  pendingWood);
    final addStone = cap(currentStone, pendingStone);

    // Actualizar base de datos
    await pool.execute(
      '''
      UPDATE resources SET
        food = food + :addFood,
        wood = wood + :addWood,
        stone = stone + :addStone,
        last_updated = :now
      WHERE user_id = :uid
      ''',
      {
        'addFood': addFood,
        'addWood': addWood,
        'addStone': addStone,
        'now': now.toIso8601String(),
        'uid': uid,
      },
    );

    return Response.ok(jsonEncode({
      'status': 'ok',
      'collected': {
        'food': addFood,
        'wood': addWood,
        'stone': addStone,
      },
      'next_collect': now.toIso8601String(),
      'max_capacity': maxCap,
    }));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al recolectar recursos: $e',
    );
  }
}
