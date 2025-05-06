import 'dart:convert';
import 'dart:io';
import 'package:guildserver/utils/timezone_config_utils.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:guildserver/db/db.dart';
import 'package:guildserver/handlers/admin_connected_handler.dart';
import 'package:guildserver/handlers/admin_race_stats_handler.dart';
import 'package:guildserver/handlers/admin_users_handler.dart';
import 'package:guildserver/handlers/battle_handler.dart';
import 'package:guildserver/handlers/build_handler.dart';
import 'package:guildserver/handlers/chat_handler.dart';
import 'package:guildserver/handlers/guild_handler.dart';
import 'package:guildserver/handlers/guild_image_handler.dart';
import 'package:guildserver/handlers/history_handler.dart';
import 'package:guildserver/handlers/online_users_handler.dart';
import 'package:guildserver/handlers/ranking_handler.dart';
import 'package:guildserver/handlers/resource_handler.dart';
import 'package:guildserver/handlers/sync_handler.dart';
import 'package:guildserver/handlers/train_handler.dart';
import 'package:guildserver/handlers/user_battle_stats_handler.dart';
import 'package:guildserver/handlers/user_handler.dart';
import 'package:guildserver/handlers/users_stats_handler.dart';
import 'package:guildserver/middleware/auth_middleware.dart';
import 'package:guildserver/services/resources_tick_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';
import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;
import '../lib/handlers/auth_handler.dart';
// ... imports idénticos ...

Future<void> main() async {
final env = DotEnv(includePlatformEnvironment: true)
    ..load();
final timezone = env['TZ'] ?? 'America/Argentina/Buenos_Aires';
configureTimezone(timezone);
  await initDb(env);

  final resourceTicker = ResourceTickService();
  resourceTicker.start();

  // Public: no requiere autenticación
  final publicRoutes = Router()
    ..post('/auth/register', registerHandler)
    ..post('/auth/login', loginHandler)
    ..get('/guild/list', listGuildsHandler)
    ..get('/guild/ranking', guildRankingHandler)
    ..get('/guild/image/<guildId>', getGuildImageHandler)
    ..get('/chat/global/history', chatGlobalHistoryHandler)
    ..get('/ranking', rankingHandler)
    ..get('/online_users', onlineUsersHandler);

//admin routes
final adminRoutes = Router()
  ..get('/admin/users', adminUsersHandler)
  ..get('/admin/connected_users', adminConnectedUsersHandler)
  ..get('/admin/server_time', serverTimeHandler)
  ..get('/admin/raza_stats', adminRazaStatsHandler);
  // Protegido: requiere autenticación por token
  final protectedRoutes = Router()
    ..post('/user/update_fcm', updateFcmTokenHandler)
    ..post('/user/profile', getUserProfile)
    ..post('/user/collect', collectResourcesHandler)
    ..post('/build/cancel', cancelConstruction)
    ..post('/train/start', startTraining)
    ..post('/train/cancel', cancelTraining)
    ..post('/sync/queues', syncQueuesHandler)
    ..post('/battle/random', randomBattleHandler)
    ..post('/battle/history', battleHistoryHandler)
    ..post('/guild/create', createGuildHandler)
    ..post('/guild/join', joinGuildHandler)
    ..post('/guild/leave', leaveGuildHandler)
    ..post('/guild/info', getGuildInfoHandler)
    ..post('/guild/upload_image', uploadGuildImageHandler)
    ..post('/guild/kick_member', kickMemberHandler)
    ..post('/guild/transfer_leadership', transferLeadershipHandler)
    ..post('/guild/update_info', updateGuildInfoHandler)
    ..post('/user/stats', getUserStatsHandler)
    ..post('/user/battle_stats', getUserBattleStatsHandler);
final staticHandler = createStaticHandler('web', defaultDocument: 'index.html');

  final handler = Cascade()
      .add(staticHandler)
      .add(adminRoutes)
      .add(authMiddleware()(protectedRoutes))
      .add(publicRoutes)
      .handler;

  final server = await serve(handler, 'localhost', 8080);
  print('Servidor iniciado en http://${server.address.host}:${server.port}');
}
Response serverTimeHandler(Request request) {
  final now = tz.TZDateTime.now(tz.local);
  return Response.ok(jsonEncode({
    'server_time': now.toIso8601String(),
  }));
}