import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Future<Response> syncQueuesHandler(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final uid = data['uid']?.toString();
  if (uid == null || uid.isEmpty) {
    return Response(400, body: 'Falta el uid.');
  }

  try {
    final pool = await getConnection();
    final now = DateTime.now();

    final result = <String, dynamic>{
      'construction': {'status': 'idle'},
      'training': {'status': 'idle'},
    };

    // --- Construcción ---
    final buildRes = await pool.execute(
      '''
      SELECT id,
             building_id,
             started_at,
             duration_seconds
        FROM construction_queue
       WHERE user_id = :uid
       LIMIT 1
      ''',
      {'uid': uid},
    );

    if (buildRes.rows.isNotEmpty) {
      final b = buildRes.rows.first.assoc();
      final buildId = b['id']!;
      final buildingId = b['building_id']!;
      final startedAt = DateTime.parse(b['started_at']!);
      final duration = int.parse(b['duration_seconds']!);
      final finishTime = startedAt.add(Duration(seconds: duration));

      if (now.isAfter(finishTime)) {
        // Completar construcción
        await pool.execute(
          'DELETE FROM construction_queue WHERE id = :buildId',
          {'buildId': buildId},
        );
        // Incrementar nivel del edificio
        await pool.execute(
          '''
          UPDATE buildings
             SET ${buildingId}_level = ${buildingId}_level + 1
           WHERE user_id = :uid
          ''',
          {'uid': uid},
        );
        result['construction'] = {
          'status': 'completed',
          'building_id': buildingId,
        };
      } else {
        // Todavía construyendo
        result['construction'] = {
          'status': 'building',
          'building_id': buildingId,
          'remaining_seconds': finishTime.difference(now).inSeconds,
        };
      }
    }

    // --- Entrenamiento ---
    final trainRes = await pool.execute(
      '''
      SELECT id,
             unit_type,
             quantity,
             started_at,
             duration_seconds
        FROM training_queue
       WHERE user_id = :uid
       LIMIT 1
      ''',
      {'uid': uid},
    );

    if (trainRes.rows.isNotEmpty) {
      final t = trainRes.rows.first.assoc();
      final queueId = t['id']!;
      final unitType = t['unit_type']!;
      final qty = int.parse(t['quantity']!);
      final startedAt = DateTime.parse(t['started_at']!);
      final duration = int.parse(t['duration_seconds']!);
      final finishTime = startedAt.add(Duration(seconds: duration));

      if (now.isAfter(finishTime)) {
        // Completar entrenamiento
        await pool.execute(
          'DELETE FROM training_queue WHERE id = :queueId',
          {'queueId': queueId},
        );
        // Añadir unidades al ejército
        await pool.execute(
          '''
          INSERT INTO army (user_id, unit_type, quantity)
          VALUES (:uid, :unitType, :qty)
          ON DUPLICATE KEY UPDATE quantity = quantity + :qty
          ''',
          {
            'uid': uid,
            'unitType': unitType,
            'qty': qty,
          },
        );
        result['training'] = {
          'status': 'completed',
          'unit_type': unitType,
          'quantity': qty,
        };
      } else {
        // Todavía entrenando
        result['training'] = {
          'status': 'training',
          'unit_type': unitType,
          'quantity': qty,
          'remaining_seconds': finishTime.difference(now).inSeconds,
        };
      }
    }

    return Response.ok(jsonEncode(result));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al sincronizar colas: $e',
    );
  }
}
