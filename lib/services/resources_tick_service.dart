import 'dart:async';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

final Map<String, int> baseProductionPerHour = {
  'farm': 50,
  'lumbermill': 30,
  'stonemine': 20,
};

class ResourceTickService {
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    print('⏱ Resource tick iniciado.');
  }

  void stop() {
    _timer?.cancel();
    print('🛑 Resource tick detenido.');
  }

  Future<void> _tick() async {
    final pool = await getConnection();
    final now = DateTime.now();
    print('▶ Recolectando recursos: $now');

    try {
      // 1️⃣ Obtener todos los usuarios con sus niveles y recursos
      final result = await pool.execute('''
        SELECT
          r.user_id,
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
      ''', {});

      for (final row in result.rows) {
        final r = row.assoc();
        final uid           = r['user_id']!;
        final lastUpdated   = DateTime.parse(r['last_updated']!);
        final elapsedSecs   = now.difference(lastUpdated).inSeconds;
        if (elapsedSecs < 60) continue;

        final currentFood   = int.parse(r['food']!);
        final currentWood   = int.parse(r['wood']!);
        final currentStone  = int.parse(r['stone']!);
        final farmLevel     = int.parse(r['farm_level']!);
        final lumberLevel   = int.parse(r['lumbermill_level']!);
        final stoneLevel    = int.parse(r['stone_mine_level']!);
        final warehouseLevel= int.parse(r['warehouse_level']!);
        final maxCap        = warehouseLevel * 500;

        // 2️⃣ Calcular producción pendiente
        int calcPending(int base, int level) =>
            (elapsedSecs / 3600 * base * level).floor();

        final pendingFood  = calcPending(baseProductionPerHour['farm']!, farmLevel);
        final pendingWood  = calcPending(baseProductionPerHour['lumbermill']!, lumberLevel);
        final pendingStone = calcPending(baseProductionPerHour['stonemine']!, stoneLevel);

        // 3️⃣ Ajustar para no exceder la capacidad
        int capAdd(int current, int toAdd) {
          final total = current + toAdd;
          final allowed = total > maxCap ? maxCap - current : toAdd;
          return allowed.clamp(0, maxCap);
        }

        final addFood  = capAdd(currentFood, pendingFood);
        final addWood  = capAdd(currentWood, pendingWood);
        final addStone = capAdd(currentStone, pendingStone);

        // 4️⃣ Si hay algo que aplicar, actualizar resources
        if (addFood > 0 || addWood > 0 || addStone > 0) {
          await pool.execute('''
            UPDATE resources SET
              food         = food + :f,
              wood         = wood + :w,
              stone        = stone + :s,
              last_updated = :now
            WHERE user_id = :uid
          ''', {
            'f': addFood,
            'w': addWood,
            's': addStone,
            'now': now.toIso8601String(),
            'uid': uid,
          });
          print('✓ $uid produjo: food=$addFood, wood=$addWood, stone=$addStone');
        }

        // 5️⃣ Registrar en resource_stats
        await pool.execute('''
          INSERT INTO resource_stats
            (user_id, total_food, total_wood, total_stone, last_updated)
          VALUES
            (:uid, :f, :w, :s, :now)
          ON DUPLICATE KEY UPDATE
            total_food  = total_food + :f,
            total_wood  = total_wood + :w,
            total_stone = total_stone + :s,
            last_updated = :now
        ''', {
          'uid': uid,
          'f': addFood,
          'w': addWood,
          's': addStone,
          'now': now.toIso8601String(),
        });
      }
    } catch (e, st) {
      print('❌ Error en ResourceTickService: $e');
      print(st);
    }
  }
}
