// lib/handlers/unit_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:guildserver/catalog/unit_catalog.dart';

/// Devuelve la lista de unidades disponibles para todas las razas.
/// Cada objeto JSON incluye todos los campos necesarios (costes, tiempo, estadísticas…).
Future<Response> unitListHandler(Request request) async {
  try {
    // Transformamos el Map<String, UnitData> en una lista de Map<String, dynamic>
    final units = unitCatalog.entries.map((entry) {
      final u = entry.value;
      return {
        'id': u.id,
        'name': u.name,
        'requiredRace': u.requiredRace,
        'hp': u.hp,
        'atk': u.atk,
        'def': u.def,
        'speed': u.speed,
        'range': u.range,
        'accuracy': u.accuracy,
        'critRate': u.critRate,
        'critDamage': u.critDamage,
        'evasion': u.evasion,
        'capacity': u.capacity,
        'costWood': u.costWood,
        'costStone': u.costStone,
        'costFood': u.costFood,
        'trainTimeSecs': u.trainTimeSecs,
      };
    }).toList();

    return Response.ok(
      jsonEncode(units),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('unitListHandler error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al listar unidades'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
