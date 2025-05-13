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
    final username   = data['username']   as String?;
    final email      = data['email']      as String?;
    final password   = data['password']   as String?;   // <‑‑ llega claro
    final raceId     = data['race']       as String?;
    final fcmToken   = data['fcm_token']  as String?;   // opcional

    if ([username, email, password, raceId].any((e) => e == null)) {
      return Response(400, body: 'Faltan campos obligatorios.');
    }

    // hash seguro
    final hashedPassword = BCrypt.hashpw(password!, BCrypt.gensalt());

    final uid   = const Uuid().v4();
    final token = const Uuid().v4();

    // INSERT principal
    await conn.execute(
      '''
      INSERT INTO users
        (id, username, email, password_hash, race, elo, session_token, fcm_token)
      VALUES
        (:id, :username, :email, :hash, :race, 1000, :token, :fcm)
      ''',
      {
        'id': uid,
        'username': username,
        'email': email,
        'hash': hashedPassword,
        'race': raceId,
        'token': token,
        'fcm': fcmToken
      },
    );

    // packs iniciales
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
      VALUES (:uid, 1, 1, 1, 1, 1)
      ''',
      {'uid': uid},
    );

    await conn.execute(
      'INSERT INTO resource_stats (user_id) VALUES (:uid)',
      {'uid': uid},
    );

    return Response.ok(jsonEncode({
  'ok'      : true,
      'uid': uid,
      'username': username,
      'token': token,
    }));
  } catch (e) {
    return Response(500, body: 'Error al registrar usuario: $e');
  }
}
// ----------------------- LOGIN -------------------------------------
Future<Response> loginHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final identifier = data['identifier'] as String?;   // <- único identificador
    final password   = data['password']   as String?;

    if (identifier == null || password == null) {
      return Response(400, body: 'Faltan credenciales.');
    }

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
    final uid       = row.colAt(0)!;
    final username  = row.colAt(1);
    final hashSaved = row.colAt(2);

    if (!BCrypt.checkpw(password, hashSaved!)) {
      return Response(401, body: 'Contraseña incorrecta.');
    }

    final token = const Uuid().v4();
    await conn.execute(
      'UPDATE users SET session_token = :t WHERE id = :uid',
      {'t': token, 'uid': uid},
    );

    return Response.ok(jsonEncode({
      'ok': true,
      'uid': uid,
      'username': username,
      'token': token,
    }));
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
