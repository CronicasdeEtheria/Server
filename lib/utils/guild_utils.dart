import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Future<void> recalculateGuildTrophies(String guildId) async {
  // Obtener el pool de conexiones
  final pool = await getConnection();

  // Sumar el elo de todos los miembros
  final sumRes = await pool.execute(
    '''
    SELECT
      SUM(u.elo) AS sum_elo
    FROM users u
    JOIN guild_members gm ON u.id = gm.user_id
    WHERE gm.guild_id = :guildId
    ''',
    {'guildId': guildId},
  );

  // Extraer y parsear el resultado
  final row     = sumRes.rows.first.assoc();
  final sumElo  = row['sum_elo'] != null ? int.parse(row['sum_elo']!) : 0;
  final trophies = (sumElo / 2).floor();

  // Actualizar el total de trofeos en la tabla guilds
  await pool.execute(
    '''
    UPDATE guilds
       SET total_trophies = :trophies
     WHERE id = :guildId
    ''',
    {
      'trophies': trophies,
      'guildId' : guildId,
    },
  );
}
