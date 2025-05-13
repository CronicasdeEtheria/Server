// lib/handlers/maps_handler.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/db.dart';

class MapsHandler {
  Router get router {
    final router = Router();
    // Rutas relativas al mount('/maps', handler.router)
    router.get('/', _getMaps);
    router.get('/<mapId>/villages', _getVillages);
    router.post('/<mapId>/assign', _assignVillage);
    // Admin: Asignar aldeas faltantes a usuarios existentes
    router.post('/assign_missing', _assignMissingVillages);
    return router;
  }

  Future<Response> _getMaps(Request req) async {
    final conn = await getConnection();
    final res = await conn.execute(
      'SELECT id, name, capacity, current_count FROM maps'
    );
    final maps = res.rows.map((r) => {
      'id':            r.colAt(0),
      'name':          r.colAt(1),
      'capacity':      r.colAt(2),
      'current_count': r.colAt(3),
    }).toList();
    return Response.ok(
      jsonEncode(maps),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _getVillages(Request req, String mapId) async {
    final id = int.tryParse(mapId);
    if (id == null) {
      return Response(400, body: 'mapId inválido');
    }
    final conn = await getConnection();
    final res = await conn.execute(
      '''
      SELECT v.id, v.player_id, u.username, v.x_coord, v.y_coord
        FROM villages v
        JOIN users u ON u.id = v.player_id
       WHERE v.map_id = :mapId
      ''',
      {'mapId': id},
    );
    final villages = res.rows.map((r) => {
      'village_id': r.colAt(0),
      'player_id' : r.colAt(1),
      'username'  : r.colAt(2),
      'x'         : (r.colAt(3) as num).toDouble(),
      'y'         : (r.colAt(4) as num).toDouble(),
    }).toList();
    return Response.ok(
      jsonEncode(villages),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _assignVillage(Request req, String mapId) async {
    final conn = await getConnection();
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final playerId = body['player_id'] as String?;
    if (playerId == null) {
      return Response(400, body: 'player_id requerido');
    }
    await conn.execute(
      'CALL assign_village_to_player(:playerId, @map, @x, @y)',
      {'playerId': playerId},
    );
    final outRes = await conn.execute('SELECT @map AS map_id, @x AS x, @y AS y');
    if (outRes.rows.isEmpty) {
      return Response(500, body: 'Error al asignar aldea');
    }
    final r = outRes.rows.first;
    return Response.ok(
      jsonEncode({
        'map_id': r.colAt(0),
        'x':      (r.colAt(1) as num).toDouble(),
        'y':      (r.colAt(2) as num).toDouble(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Admin: Asigna aldeas a todos los usuarios que no tengan una asignada
  Future<Response> _assignMissingVillages(Request req) async {
    final conn = await getConnection();
    // Selecciona ids de usuarios sin aldea
    final res = await conn.execute(
      '''
      SELECT u.id
        FROM users u
        LEFT JOIN villages v ON v.player_id = u.id
       WHERE v.id IS NULL
      '''
    );
    int count = 0;
    for (final row in res.rows) {
      final pid = row.colAt(0) as String;
      await conn.execute(
        'CALL assign_village_to_player(:playerId, @map, @x, @y)',
        {'playerId': pid},
      );
      count++;
    }
    return Response.ok(
      'Aldeas asignadas a $count usuarios.',
      headers: {'Content-Type': 'text/plain'},
    );
  }
}
