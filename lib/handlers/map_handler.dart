import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/db.dart';

class MapsHandler {
  Router get router {
    final router = Router();
    router.get('/maps', _getMaps);
    router.get('/maps/<mapId>/villages', _getVillages);
    router.post('/maps/<mapId>/assign', _assignVillage);
    return router;
  }

  Future<Response> _getMaps(Request req) async {
    final conn = await getConnection();
    final res = await conn.execute(
      'SELECT id, name, capacity, current_count FROM maps'
    );
    final maps = res.rows.map((r) => {
      'id': r.colAt(0),
      'name': r.colAt(1),
      'capacity': r.colAt(2),
      'current_count': r.colAt(3),
    }).toList();
    return Response.ok(jsonEncode(maps), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _getVillages(Request req, String mapId) async {
    final conn = await getConnection();
    final res = await conn.execute(
      '''
      SELECT v.id, v.player_id, u.username, v.x_coord, v.y_coord
        FROM villages v
        JOIN users u ON u.id = v.player_id
       WHERE v.map_id = ?
      ''',
      [int.parse(mapId)] as Map<String, dynamic>?
    );
    final villages = res.rows.map((r) => {
      'village_id': r.colAt(0),
      'player_id': r.colAt(1),
      'username': r.colAt(2),
      'x': (r.colAt(3) as num).toDouble(),
      'y': (r.colAt(4) as num).toDouble(),
    }).toList();
    return Response.ok(jsonEncode(villages), headers: {'Content-Type': 'application/json'});
  }

  Future<Response> _assignVillage(Request req, String mapId) async {
    final conn = await getConnection();
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final playerId = body['player_id'] as String?;
    if (playerId == null) {
      return Response(400, body: 'player_id requerido');
    }
    // Llamada al procedimiento almacenado
    await conn.execute(
      'CALL assign_village_to_player(:playerId, @map, @x, @y)',
      {'playerId': playerId},
    );
    final outRes = await conn.execute('SELECT @map AS map_id, @x AS x, @y AS y');
    if (outRes.rows.isEmpty) {
      return Response(500, body: 'Error al asignar aldea');
    }
    final r = outRes.rows.first;
    final assigned = {
      'map_id': r.colAt(0),
      'x': (r.colAt(1) as num).toDouble(),
      'y': (r.colAt(2) as num).toDouble(),
    };
    return Response.ok(jsonEncode(assigned), headers: {'Content-Type': 'application/json'});
  }
}
