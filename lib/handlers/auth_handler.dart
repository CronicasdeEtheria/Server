import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';

/// ----------------------- REGISTER ----------------------------------
Future<Response> registerHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final username = data['username']   as String?;
    final email    = data['email']      as String?;
    final password = data['password']   as String?;
    final raceId   = data['race']       as String?;
    final fcmToken = data['fcm_token']  as String?;

    if ([username, email, password, raceId].any((e) => e == null)) {
      return Response(400, body: 'Faltan campos obligatorios.');
    }

    // 1) Hash seguro y creación de IDs
    final hashedPassword = BCrypt.hashpw(password!, BCrypt.gensalt());
    final uid   = const Uuid().v4();
    final token = const Uuid().v4();

    // 2) INSERT usuario
    await conn.execute(
      '''
      INSERT INTO users
        (id, username, email, password_hash, race, elo, session_token, fcm_token)
      VALUES
        (:uid, :username, :email, :hash, :race, 1000, :token, :fcm)
      ''',
      {
        'uid': uid,
        'username': username,
        'email': email,
        'hash': hashedPassword,
        'race': raceId,
        'token': token,
        'fcm': fcmToken
      },
    );

    // 3) INSERT packs iniciales
    await conn.execute(
      '''
      INSERT INTO resources (user_id, food, wood, stone, gold, last_updated)
      VALUES (:uid, 500, 500, 500, 500, NOW())
      ''',
      {'uid': uid},
    );
    await conn.execute(
      '''
      INSERT INTO buildings
        (user_id, townhall_level, farm_level, lumbermill_level,
         stone_mine_level, warehouse_level)
      VALUES
        (:uid, 1, 1, 1, 1, 1)
      ''',
      {'uid': uid},
    );
    await conn.execute(
      'INSERT INTO resource_stats (user_id) VALUES (:uid)',
      {'uid': uid},
    );

    // 4) LLAMADA al procedimiento para asignar aldea
    await conn.execute(
      'CALL assign_village_to_player(:uid, @map, @x, @y)',
      {'uid': uid},
    );

    // 5) OBTENER coordenadas asignadas
    final outRes = await conn.execute(
      'SELECT @map AS map_id, @x AS x, @y AS y',
    );
    if (outRes.rows.isEmpty) {
      throw Exception('No se obtuvieron coordenadas de aldea');
    }
    final row    = outRes.rows.first;
    final mapId  = row.colAt(0)! as int;
    final x      = (row.colAt(1)! as num).toDouble();
    final y      = (row.colAt(2)! as num).toDouble();

    // 6) Responder con token + datos de aldea
    return Response.ok(jsonEncode({
      'ok'      : true,
      'uid'     : uid,
      'username': username,
      'token'   : token,
      'village' : {
        'map_id': mapId,
        'x':      x,
        'y':      y,
      }
    }), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response(500, body: 'Error al registrar usuario: $e');
  }
}


/// ----------------------- LOGIN -------------------------------------
Future<Response> loginHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data       = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final identifier = data['identifier'] as String?;
    final password   = data['password']   as String?;
    if (identifier == null || password == null) {
      return Response(400, body: 'Faltan credenciales.');
    }

    // 1) Validar usuario
    final result = await conn.execute(
      '''
      SELECT id, username, password_hash
      FROM users
      WHERE email = :ident OR username = :ident
      ''',
      {'ident': identifier},
    );
    if (result.rows.isEmpty) {
      return Response(404, body: 'Usuario no encontrado.');
    }
    final row       = result.rows.first;
    final uid       = row.colAt(0)! as String;
    final username  = row.colAt(1)             as String;
    final hashSaved = row.colAt(2)!            as String;
    if (!BCrypt.checkpw(password, hashSaved)) {
      return Response(401, body: 'Contraseña incorrecta.');
    }

    // 2) Actualizar token de sesión
    final token = const Uuid().v4();
    await conn.execute(
      'UPDATE users SET session_token = :token WHERE id = :uid',
      {'token': token, 'uid': uid},
    );

    // 3) Verificar o asignar aldea
    late Map<String, dynamic> villageData;
    final villRes = await conn.execute(
      'SELECT 1 FROM villages WHERE player_id = :uid',
      {'uid': uid},
    );
    if (villRes.rows.isEmpty) {
      // No tiene aldea: asignar nueva
      await conn.execute(
        'CALL assign_village_to_player(:uid, @map, @x, @y)',
        {'uid': uid},
      );
      final outRes2 = await conn.execute(
        'SELECT @map AS map_id, @x AS x, @y AS y',
      );
      final r2 = outRes2.rows.first;
      villageData = {
        'map_id': r2.colAt(0)! as int,
        'x':      (r2.colAt(1)! as num).toDouble(),
        'y':      (r2.colAt(2)! as num).toDouble(),
      };
    } else {
      // Ya tiene aldea: recuperar existentes
      final vRes = await conn.execute(
        '''
        SELECT map_id, x_coord AS x, y_coord AS y
          FROM villages
         WHERE player_id = :uid
        ''',
        {'uid': uid},
      );
      final vr = vRes.rows.first;
      villageData = {
        'map_id': vr.colAt(0)! as int,
        'x':      (vr.colAt(1)! as num).toDouble(),
        'y':      (vr.colAt(2)! as num).toDouble(),
      };
    }

    // 4) Responder con token + datos de aldea
    return Response.ok(jsonEncode({
      'ok'      : true,
      'uid'     : uid,
      'username': username,
      'token'   : token,
      'village' : villageData,
    }), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response(500, body: 'Error al iniciar sesión: $e');
  }
}

/// -------------- ACTUALIZAR TOKEN FCM -------------------------------
Future<Response> updateFcmTokenHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final uid       = data['uid'];
    final token     = data['token'];
    final fcmToken  = data['fcm_token'];

    if ([uid, token, fcmToken].any((e) => e == null)) {
      return Response(400, body: 'Faltan parámetros.');
    }

    final result = await conn.execute(
      'SELECT id FROM users WHERE id = :uid AND session_token = :tok',
      {'uid': uid, 'tok': token},
    );

    if (result.rows.isEmpty) {
      return Response(403, body: 'Token inválido.');
    }

    await conn.execute(
      'UPDATE users SET fcm_token = :f WHERE id = :uid',
      {'f': fcmToken, 'uid': uid},
    );

    return Response.ok(jsonEncode({'status': 'updated'}));
  } catch (e) {
    return Response(500, body: 'Error al actualizar FCM token: $e');
  }
}
