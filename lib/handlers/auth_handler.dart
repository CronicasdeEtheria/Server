import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:guildserver/db/db.dart';

Future<Response> registerHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final username = data['username'];
    final email = data['email'];
    final password = data['password'];
    final race = data['race'];
    final fcmToken = data['fcm_token'];

    if ([username, email, password, race].any((e) => e == null)) {
      return Response(400, body: 'Faltan campos obligatorios.');
    }

    final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
    final uid = const Uuid().v4();
    final token = const Uuid().v4();

    await conn.execute('''
      INSERT INTO users (id, username, email, password, race, elo, session_token, fcm_token)
      VALUES (:id, :username, :email, :password, :race, 1000, :token, :fcm)
    ''', {
      'id': uid,
      'username': username,
      'email': email,
      'password': hashedPassword,
      'race': race,
      'token': token,
      'fcm': fcmToken
    });

    await conn.execute('''
      INSERT INTO resources (user_id, food, wood, stone, gold, last_updated)
      VALUES (:uid, 500, 500, 500, 500, NOW())
    ''', {'uid': uid});

    await conn.execute('''
      INSERT INTO buildings (user_id, farm_level, lumbermill_level, stone_mine_level, warehouse_level)
      VALUES (:uid, 1, 1, 1, 1)
    ''', {'uid': uid});

    await conn.execute('INSERT INTO resource_stats (user_id) VALUES (:uid)', {'uid': uid});

    return Response.ok(jsonEncode({
      'status': 'ok',
      'uid': uid,
      'token': token,
      'username': username,
    }));
  } catch (e) {
    return Response(500, body: 'Error al registrar usuario: $e');
  }
}

Future<Response> loginHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final email = data['email'];
    final password = data['password'];

    if ([email, password].any((e) => e == null)) {
      return Response(400, body: 'Faltan credenciales.');
    }

    final result = await conn.execute(
      'SELECT id, username, password FROM users WHERE email = :email',
      {'email': email},
    );

    if (result.rows.isEmpty) return Response(404, body: 'Usuario no encontrado.');

    final row = result.rows.first;
    final uid = row.colAt(0)!;
    final username = row.colAt(1);
    final hash = row.colAt(2);

    final ok = BCrypt.checkpw(password, hash!);
    if (!ok) return Response(401, body: 'Contraseña incorrecta.');

    final token = const Uuid().v4();
    await conn.execute(
      'UPDATE users SET session_token = :token WHERE id = :uid',
      {'token': token, 'uid': uid},
    );

    return Response.ok(jsonEncode({
      'status': 'ok',
      'uid': uid,
      'username': username,
      'token': token,
    }));
  } catch (e) {
    return Response(500, body: 'Error al iniciar sesión: $e');
  }
}

Future<Response> updateFcmTokenHandler(Request request) async {
  try {
    final conn = await getConnection();

    final data = jsonDecode(await request.readAsString());
    final uid = data['uid'];
    final token = data['token'];
    final fcmToken = data['fcm_token'];

    if ([uid, token, fcmToken].any((e) => e == null)) {
      return Response(400, body: 'Faltan parámetros.');
    }

    final result = await conn.execute(
      'SELECT id FROM users WHERE id = :uid AND session_token = :token',
      {'uid': uid, 'token': token},
    );

    if (result.rows.isEmpty) {
      return Response(403, body: 'Token inválido.');
    }

    await conn.execute(
      'UPDATE users SET fcm_token = :fcm WHERE id = :uid',
      {'fcm': fcmToken, 'uid': uid},
    );

    return Response.ok(jsonEncode({'status': 'updated'}));
  } catch (e) {
    return Response(500, body: 'Error al actualizar FCM token: $e');
  }
}
