import 'dart:convert';
import 'dart:io';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/utils/guild_utils.dart';
import 'package:path/path.dart' as p;

final _uuid = Uuid();

/// Handler para crear un gremio con opción de icono predeterminado.
Future<Response> createGuildHandler(Request request) async {
  final pool = await getConnection();

  // Obtener userId desde middleware
  final String? uid = request.context['userId'] as String?;
  if (uid == null) {
    return Response(401,
      body: jsonEncode({'error': 'No autenticado.'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // Leer datos del body
  final Map<String, dynamic> data =
      jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final String? name = (data['name'] as String?)?.trim();
  final String description = (data['description'] as String? ?? '').trim();
  final String? defaultIcon = (data['default_icon'] as String?)?.trim();

  if (name == null || name.isEmpty) {
    return Response(400,
      body: jsonEncode({'error': 'Nombre de gremio obligatorio.'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  try {
    // Verificar membresía previa
    final existing = await pool.execute(
      'SELECT 1 FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    if (existing.rows.isNotEmpty) {
      return Response(400,
        body: jsonEncode({'error': 'Ya perteneces a un gremio.'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Crear gremio
    final String guildId = _uuid.v4();
    await pool.execute(
      'INSERT INTO guilds (id, name, description) VALUES (:id, :name, :description)',
      {'id': guildId, 'name': name, 'description': description},
    );

    // Agregar creador como líder
    await pool.execute(
      'INSERT INTO guild_members (user_id, guild_id, is_leader) VALUES (:uid, :guildId, TRUE)',
      {'uid': uid, 'guildId': guildId},
    );

    // Icono predeterminado (asset) en servidor
    if (defaultIcon != null && defaultIcon.isNotEmpty) {
      final baseDir = Directory.current.path;
      final srcPath = p.join(baseDir, 'assets', 'guild_icons', defaultIcon);
      final srcAsset = File(srcPath);
      final dstDir = Directory(p.join(baseDir, 'storage', 'guilds'));
      if (!await dstDir.exists()) await dstDir.create(recursive: true);
      final dstPath = p.join(dstDir.path, '$guildId.jpg');
      if (await srcAsset.exists()) {
        await srcAsset.copy(dstPath);
        await pool.execute(
          'UPDATE guilds SET image_url = :url WHERE id = :guildId',
          {'url': dstPath, 'guildId': guildId},
        );
      } else {
        print('⚠️ Asset no encontrado: $srcPath');
      }
    }

    // Calcular trofeos
    final eloRes = await pool.execute(
      'SELECT elo FROM users WHERE id = :uid',
      {'uid': uid},
    );
    final int elo = eloRes.rows.first.typedColAt<int>(0) ?? 0;
    final int trophies = (elo / 2).floor();
    await pool.execute(
      'UPDATE guilds SET total_trophies = :trophies WHERE id = :guildId',
      {'trophies': trophies, 'guildId': guildId},
    );

    return Response.ok(
      jsonEncode({'status': 'ok', 'guild_id': guildId}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al crear gremio: $e'}),
      headers: {'Content-Type': 'application/json'},
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
  final uid = request.context['userId'] as String?;
  if (uid == null) {
    return Response(401,
      body: jsonEncode({'error': 'No autenticado.'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  try {
    final res = await pool.execute(
      'SELECT guild_id, is_leader FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );
    if (res.rows.isEmpty) {
      return Response(400,
        body: jsonEncode({'error': 'No estás en un gremio.'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final row = res.rows.first;
    final guildId = row.assoc()['guild_id'] as String;
    final bool isLeader = row.typedColAt<bool>(1) ?? false;

    await pool.execute(
      'DELETE FROM guild_members WHERE user_id = :uid',
      {'uid': uid},
    );

    final membersRes = await pool.execute(
      'SELECT user_id FROM guild_members WHERE guild_id = :guildId',
      {'guildId': guildId},
    );

    if (membersRes.rows.isEmpty) {
      await pool.execute(
        'DELETE FROM guilds WHERE id = :guildId',
        {'guildId': guildId},
      );
      final imageFile = File('storage/guilds/$guildId.jpg');
      if (await imageFile.exists()) await imageFile.delete();

      return Response.ok(
        jsonEncode({'status': 'guild_deleted'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (isLeader) {
      final newLeader = membersRes.rows.first.assoc()['user_id'] as String;
      await pool.execute(
        'UPDATE guild_members SET is_leader = TRUE WHERE user_id = :newLeader',
        {'newLeader': newLeader},
      );
    }

    await recalculateGuildTrophies(guildId);
    return Response.ok(
      jsonEncode({'status': 'left'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> getGuildInfoHandler(Request request) async {
  final pool = await getConnection();

  final data = jsonDecode(await request.readAsString());
  final guildId = data['guild_id']?.toString();
  if (guildId == null) return Response(400, body: 'Falta guild_id.');

  try {
    // Obtenemos nombre, descripción, fecha, sumamos el ELO de los miembros
    final info = await pool.execute(
      '''
      SELECT
        g.name,
        g.description,
        g.created_at,
        COALESCE(SUM(u.elo), 0) AS sum_elo,
        COUNT(u.id) AS member_count
      FROM guilds g
      LEFT JOIN guild_members gm ON gm.guild_id = g.id
      LEFT JOIN users u ON u.id = gm.user_id
      WHERE g.id = :guildId
      GROUP BY g.id
      ''',
      {'guildId': guildId},
    );
    if (info.rows.isEmpty) {
      return Response.notFound('Gremio no encontrado.');
    }

    final row = info.rows.first.assoc();
    final name        = row['name']!;
    final description = row['description']!;
    final createdAt   = row['created_at']!;
    final sumElo      = int.parse(row['sum_elo']!);
    final trophies    = (sumElo / 2).floor();
    final memberCount = int.parse(row['member_count']!);

    // Ahora la lista de miembros con rol de líder
    final membersRes = await pool.execute(
      '''
      SELECT u.username, u.elo, gm.is_leader
      FROM guild_members gm
      JOIN users u ON u.id = gm.user_id
      WHERE gm.guild_id = :guildId
      ''',
      {'guildId': guildId},
    );
    final members = membersRes.rows.map((r) {
      final m = r.assoc();
      return {
        'username':   m['username']!,
        'elo':        int.parse(m['elo']!),
        'is_leader':  r.typedColAt<bool>(2),
      };
    }).toList();

    return Response.ok(jsonEncode({
      'name':         name,
      'description':  description,
      'created_at':   createdAt,
      'trophies':     trophies,
      'member_count': memberCount,
      'members':      members,
    }), headers: {'Content-Type': 'application/json'});
  } catch (e) {
    return Response.internalServerError(
      body: 'Error al obtener datos del gremio: $e',
    );
  }
}

// Reemplaza tu listGuildsHandler por esta versión:
Future<Response> listGuildsHandler(Request request) async {
  final pool = await getConnection();

  final params = request.url.queryParameters;
  final limit  = int.tryParse(params['limit'] ?? '')  ?? 20;
  final offset = int.tryParse(params['offset'] ?? '') ?? 0;

  try {
    // Consultamos todos los gremios, sumamos el ELO y contamos miembros
    final res = await pool.execute(
      '''
      SELECT
        g.id,
        g.name,
        g.description,
        COALESCE(SUM(u.elo), 0) AS sum_elo,
        COUNT(u.id) AS member_count
      FROM guilds g
      LEFT JOIN guild_members gm ON g.id = gm.guild_id
      LEFT JOIN users u ON u.id = gm.user_id
      GROUP BY g.id
      ORDER BY sum_elo DESC
      LIMIT :limit OFFSET :offset
      ''',
      {'limit': limit, 'offset': offset},
    );

    final guilds = res.rows.map((r) {
      final a        = r.assoc();
      final sumElo   = int.parse(a['sum_elo']!);
      final trophies = (sumElo / 2).floor();
      return {
        'id':           a['id']!,
        'name':         a['name']!,
        'description':  a['description']!,
        'trophies':     trophies,
        'member_count': int.parse(a['member_count']!),
      };
    }).toList();

    return Response.ok(jsonEncode(guilds),
        headers: {'Content-Type': 'application/json'});
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
