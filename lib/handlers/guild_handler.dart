import 'dart:convert';
import 'dart:io';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/utils/guild_utils.dart';

final _uuid = Uuid();

Future<Response> createGuildHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  final name = data['name']?.toString().trim();
  final description = data['description']?.toString().trim() ?? '';

  if (uid == null || uid.isEmpty || name == null || name.isEmpty) {
    return Response(400, body: 'Nombre y UID son obligatorios.');
  }

  try {
    // Verificar si ya pertenece a un gremio
    final existing = await pool.execute(
      'SELECT * FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    if (existing.rows.isNotEmpty) {
      return Response(400, body: 'Ya perteneces a un gremio.');
    }

    // Crear gremio
    final guildId = _uuid.v4();
    await pool.execute(
      'INSERT INTO guilds (id, name, description) VALUES (:id, :name, :description)',
      {
        'id': guildId,
        'name': name,
        'description': description,
      },
    );

    // Agregar al creador
    await pool.execute(
      'INSERT INTO guild_members (user_id, guild_id) VALUES (:uid, :guildId)',
      {
        'uid': uid,
        'guildId': guildId,
      },
    );

    // Obtener Elo del jugador y calcular trofeos
    final eloRes = await pool.execute(
      'SELECT elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    final elo = eloRes.rows.first.typedColAt<int>(0);
    final trophies = (elo! / 2).floor();

    await pool.execute(
      'UPDATE guilds SET total_trophies = :trophies WHERE id = :guildId',
      {
        'trophies': trophies,
        'guildId': guildId,
      },
    );

    return Response.ok(jsonEncode({'status': 'ok', 'guild_id': guildId}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al crear el gremio: $e',
    );
  }
}

Future<Response> joinGuildHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  final guildId = data['guild_id']?.toString();

  if (uid == null || guildId == null) {
    return Response(400, body: 'Faltan parámetros.');
  }

  try {
    final existing = await pool.execute(
      'SELECT * FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    if (existing.rows.isNotEmpty) {
      return Response(400, body: 'Ya estás en un gremio.');
    }

    await pool.execute(
      'INSERT INTO guild_members (user_id, guild_id) VALUES (:uid, :guildId)',
      {
        'uid': uid,
        'guildId': guildId,
      },
    );

    await recalculateGuildTrophies(guildId);

    return Response.ok(jsonEncode({'status': 'ok'}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al unirse al gremio: $e',
    );
  }
}

Future<Response> leaveGuildHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  if (uid == null) return Response(400, body: 'Falta uid.');

  try {
    final res = await pool.execute(
      'SELECT guild_id, is_leader FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    if (res.rows.isEmpty) {
      return Response(400, body: 'No estás en un gremio.');
    }

    final row = res.rows.first;
    final guildId = row.assoc()['guild_id'] as String;
    final isLeader = row.typedColAt<bool>(1);

    // Borrar miembro
    await pool.execute(
      'DELETE FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );

    // ¿Quedan miembros?
    final membersRes = await pool.execute(
      'SELECT user_id FROM guild_members WHERE guild_id = :guildId',
      {'guildId': guildId},
    );

    if (membersRes.rows.isEmpty) {
      // Si quedó vacío, borrar gremio e imagen
      await pool.execute(
        'DELETE FROM guilds WHERE id = :guildId',
        {'guildId': guildId},
      );
      final imageFile = File('storage/guilds/$guildId.jpg');
      if (await imageFile.exists()) await imageFile.delete();

      return Response.ok(jsonEncode({'status': 'guild_deleted'}));
    }

// isLeader es bool?
if (isLeader == true) {
  final newLeader = membersRes.rows.first.assoc()['user_id'] as String;
  await pool.execute(
    'UPDATE guild_members SET is_leader = TRUE WHERE user_id = :newLeader',
    {'newLeader': newLeader},
  );
}


    await recalculateGuildTrophies(guildId);
    return Response.ok(jsonEncode({'status': 'left'}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al salir del gremio: $e',
    );
  }
}

Future<Response> getGuildInfoHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final guildId = data['guild_id']?.toString();
  if (guildId == null) return Response(400, body: 'Falta guild_id.');

  try {
    final info = await pool.execute(
      'SELECT name, description, total_trophies, created_at FROM guilds WHERE id = :guildId',
      {'guildId': guildId},
    );
    if (info.rows.isEmpty) {
      return Response(404, body: 'Gremio no encontrado.');
    }

    final row = info.rows.first;
    final assoc = row.assoc();
    final name = assoc['name']!;
    final description = assoc['description']!;
    final trophies = row.typedColAt<int>(2);
    final createdAt = assoc['created_at']!;

    final membersRes = await pool.execute(
      '''
      SELECT u.username, u.elo
        FROM users u
        JOIN guild_members gm ON gm.user_id = u.id
       WHERE gm.guild_id = :guildId
      ''',
      {'guildId': guildId},
    );
    final members = membersRes.rows.map((r) {
      final m = r.assoc();
      return {
        'username': m['username']!,
        'elo': int.parse(m['elo']!),
      };
    }).toList();

    return Response.ok(jsonEncode({
      'name': name,
      'description': description,
      'trophies': trophies,
      'created_at': createdAt,
      'members': members,
    }));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener datos del gremio: $e',
    );
  }
}

Future<Response> listGuildsHandler(Request request) async {
  final pool = await getConnection();

  final params = request.url.queryParameters;
  final limit = int.tryParse(params['limit'] ?? '') ?? 20;
  final offset = int.tryParse(params['offset'] ?? '') ?? 0;

  try {
    final res = await pool.execute(
      '''
      SELECT
        g.id,
        g.name,
        g.description,
        g.total_trophies AS trophies,
        COUNT(gm.user_id) AS member_count
      FROM guilds g
      LEFT JOIN guild_members gm ON g.id = gm.guild_id
      GROUP BY g.id
      ORDER BY g.total_trophies DESC
      LIMIT :limit OFFSET :offset
      ''',
      {
        'limit': limit,
        'offset': offset,
      },
    );

    final guilds = res.rows.map((r) {
      final a = r.assoc();
      return {
        'id': a['id']!,
        'name': a['name']!,
        'description': a['description']!,
        'trophies': int.parse(a['trophies']!),
        'member_count': int.parse(a['member_count']!),
      };
    }).toList();

    return Response.ok(jsonEncode(guilds));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al listar gremios: $e',
    );
  }
}

Future<Response> kickMemberHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  final targetId = data['target_id']?.toString();

  if (uid == null || targetId == null) {
    return Response(400, body: 'Faltan parámetros.');
  }

  try {
    final rows = await pool.execute(
      'SELECT guild_id FROM guild_members WHERE user_id = :uid AND is_leader = TRUE',
      {'uid': uid},
    );
    if (rows.rows.isEmpty) {
      return Response.forbidden('No sos el líder del gremio.');
    }
    final guildId = rows.rows.first.assoc()['guild_id']!;

    if (uid == targetId) {
      return Response(400, body: 'No podés expulsarte a vos mismo.');
    }

    final check = await pool.execute(
      'SELECT * FROM guild_members WHERE user_id = :targetId AND guild_id = :guildId',
      {'targetId': targetId, 'guildId': guildId},
    );
    if (check.rows.isEmpty) {
      return Response(404, body: 'Miembro no encontrado en tu gremio.');
    }

    await pool.execute(
      'DELETE FROM guild_members WHERE user_id = :targetId',
      {'targetId': targetId},
    );
    await recalculateGuildTrophies(guildId);

    return Response.ok(jsonEncode({'status': 'kicked'}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al expulsar miembro: $e',
    );
  }
}

Future<Response> transferLeadershipHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  final targetId = data['target_id']?.toString();

  if (uid == null || targetId == null) {
    return Response(400, body: 'Faltan parámetros.');
  }

  try {
    final rows = await pool.execute(
      'SELECT guild_id FROM guild_members WHERE user_id = :uid AND is_leader = TRUE',
      {'uid': uid},
    );
    if (rows.rows.isEmpty) {
      return Response.forbidden('No sos el líder actual.');
    }
    final guildId = rows.rows.first.assoc()['guild_id']!;

    final targetCheck = await pool.execute(
      'SELECT * FROM guild_members WHERE user_id = :targetId AND guild_id = :guildId',
      {'targetId': targetId, 'guildId': guildId},
    );
    if (targetCheck.rows.isEmpty) {
      return Response(404, body: 'El nuevo líder no está en tu gremio.');
    }

    await pool.execute(
      'UPDATE guild_members SET is_leader = FALSE WHERE user_id = :uid',
      {'uid': uid},
    );
    await pool.execute(
      'UPDATE guild_members SET is_leader = TRUE WHERE user_id = :targetId',
      {'targetId': targetId},
    );

    return Response.ok(jsonEncode({'status': 'leadership_transferred'}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al transferir liderazgo: $e',
    );
  }
}

Future<Response> updateGuildInfoHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final uid = data['uid']?.toString();
  final name = data['name']?.toString().trim();
  final description = data['description']?.toString().trim();

  if (uid == null || (name == null && description == null)) {
    return Response(400, body: 'Faltan parámetros.');
  }

  try {
    final rows = await pool.execute(
      '''
      SELECT g.id
        FROM guilds g
        JOIN guild_members gm ON gm.guild_id = g.id
       WHERE gm.user_id = :uid AND gm.is_leader = TRUE
      ''',
      {'uid': uid},
    );
    if (rows.rows.isEmpty) {
      return Response(403, body: 'No sos líder de ningún gremio.');
    }
    final guildId = rows.rows.first.assoc()['id']!;

    if (name != null && name.isNotEmpty) {
      await pool.execute(
        'UPDATE guilds SET name = :name WHERE id = :guildId',
        {'name': name, 'guildId': guildId},
      );
    }
    if (description != null) {
      await pool.execute(
        'UPDATE guilds SET description = :description WHERE id = :guildId',
        {'description': description, 'guildId': guildId},
      );
    }

    return Response.ok(jsonEncode({'status': 'updated'}));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al actualizar gremio: $e',
    );
  }
}

Future<Response> guildRankingHandler(Request request) async {
  final pool = await getConnection();

  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;

  try {
    final res = await pool.execute(
      '''
      SELECT
        g.name,
        g.total_trophies AS trophies,
        COUNT(gm.user_id) AS members
      FROM guilds g
      LEFT JOIN guild_members gm ON g.id = gm.guild_id
      GROUP BY g.id
      ORDER BY g.total_trophies DESC
      LIMIT :limit
      ''',
      {'limit': limit},
    );

    final data = res.rows.map((r) {
      final a = r.assoc();
      return {
        'name': a['name']!,
        'trophies': int.parse(a['trophies']!),
        'members': int.parse(a['members']!),
      };
    }).toList();

    return Response.ok(jsonEncode(data));
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener ranking de gremios: $e',
    );
  }
}
