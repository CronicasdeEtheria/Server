import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';
import 'package:guildserver/catalog/unit_catalog.dart';

Map<String, dynamic> calculateTrainingCost(String unitId, int quantity) {
  final unit = unitCatalog[unitId]!;
  return {
    'duration_seconds': unit.trainTimeSecs * quantity,
    'wood': unit.costWood * quantity,
    'stone': unit.costStone * quantity,
    'food': unit.costFood * quantity,
  };
}

Future<Response> startTraining(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  final unitType = data['unit_type']?.toString();
  final quantity = data['quantity'] is int ? data['quantity'] as int : int.tryParse('${data['quantity']}');

  if (uid == null || unitType == null || quantity == null) {
    return Response(400, body: 'Faltan parámetros.');
  }
  if (quantity > 20) {
    return Response(400, body: 'Máximo 20 unidades por entrenamiento.');
  }
  final unit = unitCatalog[unitType];
  if (unit == null) {
    return Response(400, body: 'Unidad inválida.');
  }

  try {
    final pool = await getConnection();

    // Verificar raza si aplica
    if (unit.requiredRace != null) {
      final res = await pool.execute(
        'SELECT race FROM users WHERE id = :uid',
        {'uid': uid},
      );
      final userRace = res.rows.first.assoc()['race']!;
      if (userRace != unit.requiredRace) {
        return Response(403, body: 'Unidad no disponible para tu raza.');
      }
    }

    // Costos totales
    final costWood  = unit.costWood * quantity;
    final costStone = unit.costStone * quantity;
    final costFood  = unit.costFood * quantity;

    // Verificar recursos
    final rRes = await pool.execute(
      'SELECT wood, stone, food FROM resources WHERE user_id = :uid',
      {'uid': uid},
    );
    final r = rRes.rows.first.assoc();
    final haveWood  = int.parse(r['wood']!);
    final haveStone = int.parse(r['stone']!);
    final haveFood  = int.parse(r['food']!);
    if (haveWood < costWood || haveStone < costStone || haveFood < costFood) {
      return Response(400, body: 'Recursos insuficientes.');
    }

    final duration = unit.trainTimeSecs * quantity;

    // Descontar recursos
    await pool.execute(
      '''
      UPDATE resources SET
        wood  = wood  - :w,
        stone = stone - :s,
        food  = food  - :f
      WHERE user_id = :uid
      ''',
      {'w': costWood, 's': costStone, 'f': costFood, 'uid': uid},
    );

    // Insertar en cola (suponiendo started_at DEFAULT CURRENT_TIMESTAMP)
    await pool.execute(
      '''
      INSERT INTO training_queue
        (user_id, unit_type, quantity, duration_seconds)
      VALUES
        (:uid, :unitType, :qty, :dur)
      ''',
      {'uid': uid, 'unitType': unitType, 'qty': quantity, 'dur': duration},
    );

    return Response.ok(jsonEncode({
      'status': 'queued',
      'unit_type': unitType,
      'quantity': quantity,
      'duration_seconds': duration,
    }));
  } catch (e) {
    return Response.internalServerError(body: 'Error al iniciar entrenamiento: $e');
  }
}

Future<Response> cancelTraining(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();

    // Obtener entrenamiento activo
    final qRes = await pool.execute(
      'SELECT id, unit_type, quantity FROM training_queue WHERE user_id = :uid LIMIT 1',
      {'uid': uid},
    );
    if (qRes.rows.isEmpty) {
      return Response(400, body: 'No hay entrenamiento activo.');
    }
    final q = qRes.rows.first.assoc();
    final queueId  = q['id']!;
    final unitType = q['unit_type']!;
    final qty      = int.parse(q['quantity']!);
    final unit     = unitCatalog[unitType];
    if (unit == null) {
      return Response(500, body: 'Unidad desconocida.');
    }

    // Calcular reembolso (50%)
    final refundWood  = (unit.costWood * qty * 0.5).floor();
    final refundStone = (unit.costStone * qty * 0.5).floor();
    final refundFood  = (unit.costFood * qty * 0.5).floor();

    // Eliminar de la cola
    await pool.execute(
      'DELETE FROM training_queue WHERE id = :id',
      {'id': queueId},
    );

    // Devolver recursos
    await pool.execute(
      '''
      UPDATE resources SET
        wood  = wood  + :w,
        stone = stone + :s,
        food  = food  + :f
      WHERE user_id = :uid
      ''',
      {
        'w': refundWood,
        's': refundStone,
        'f': refundFood,
        'uid': uid,
      },
    );

    return Response.ok(jsonEncode({
      'status': 'cancelled',
      'refunded': {
        'wood': refundWood,
        'stone': refundStone,
        'food': refundFood,
      },
      'unit_type': unitType,
      'quantity': qty,
    }));
  } catch (e) {
    return Response.internalServerError(body: 'Error al cancelar entrenamiento: $e');
  }
}

Future<Response> checkTrainingStatus(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();
    final tRes = await pool.execute(
      '''
      SELECT id, unit_type, quantity, started_at, duration_seconds
        FROM training_queue
       WHERE user_id = :uid
      ''',
      {'uid': uid},
    );
    if (tRes.rows.isEmpty) {
      return Response.ok(jsonEncode({'status': 'idle'}));
    }

    final t = tRes.rows.first.assoc();
    final queueId  = t['id']!;
    final unitType = t['unit_type']!;
    final qty      = int.parse(t['quantity']!);
    final started  = DateTime.parse(t['started_at']!);
    final dur      = int.parse(t['duration_seconds']!);
    final finish   = started.add(Duration(seconds: dur));
    final now      = DateTime.now();

    if (now.isAfter(finish)) {
      // Completar entrenamiento
      await pool.execute(
        'DELETE FROM training_queue WHERE id = :id',
        {'id': queueId},
      );
      await pool.execute(
        '''
        INSERT INTO army (user_id, unit_type, quantity)
        VALUES (:uid, :unitType, :qty)
        ON DUPLICATE KEY UPDATE
          quantity = quantity + :qty
        ''',
        {'uid': uid, 'unitType': unitType, 'qty': qty},
      );

      return Response.ok(jsonEncode({
        'status': 'completed',
        'unit_type': unitType,
        'quantity': qty,
      }));
    } else {
      // Aún entrenando
      return Response.ok(jsonEncode({
        'status': 'training',
        'unit_type': unitType,
        'quantity': qty,
        'remaining_seconds': finish.difference(now).inSeconds,
      }));
    }
  } catch (e) {
    return Response.internalServerError(body: 'Error al revisar entrenamiento: $e');
  }
}
