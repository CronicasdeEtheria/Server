import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

final Map<String, int> baseProductionPerHour = {
  'farm': 50,
  'lumbermill': 30,
  'stonemine': 20,
};

Future<void> main() async {
  // Cargar variables de entorno e inicializar pool
  final env = DotEnv()..load();
  await initDb(env);

  final now = DateTime.now();
  print('Tick iniciado: $now');

  // Obtener el pool de conexiones
  final pool = await getConnection();

  // Obtener todos los usuarios con sus niveles y recursos
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
    final uid          = r['user_id']!;
    final lastUpdated  = DateTime.parse(r['last_updated']!);
    final elapsedSecs  = now.difference(lastUpdated).inSeconds;

    // Evitar ticks demasiado frecuentes
    if (elapsedSecs < 60) continue;

    // Valores actuales
    final currentFood   = int.parse(r['food']!);
    final currentWood   = int.parse(r['wood']!);
    final currentStone  = int.parse(r['stone']!);

    // Niveles de producción y capacidad
    final farmLevel     = int.parse(r['farm_level']!);
    final lumberLevel   = int.parse(r['lumbermill_level']!);
    final stoneLevel    = int.parse(r['stone_mine_level']!);
    final warehouseLevel= int.parse(r['warehouse_level']!);
    final maxCap        = warehouseLevel * 500;

    // Calcular producción pendiente
    int calcPending(int base, int level) =>
      (elapsedSecs / 3600 * base * level).floor();

    final pendingFood  = calcPending(baseProductionPerHour['farm']!, farmLevel);
    final pendingWood  = calcPending(baseProductionPerHour['lumbermill']!, lumberLevel);
    final pendingStone = calcPending(baseProductionPerHour['stonemine']!, stoneLevel);

    // Ajustar para no exceder la capacidad máxima
    int capAdd(int current, int toAdd) {
      final total = current + toAdd;
      final allowed = total > maxCap ? maxCap - current : toAdd;
      return allowed.clamp(0, maxCap);
    }

    final addFood  = capAdd(currentFood, pendingFood);
    final addWood  = capAdd(currentWood, pendingWood);
    final addStone = capAdd(currentStone, pendingStone);

    // Si hay producción para aplicar, actualizar tabla de recursos
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

      print('✓ $uid recibió: food=$addFood, wood=$addWood, stone=$addStone');
    }
  }

  print('Tick completado.');
  exit(0);
}
