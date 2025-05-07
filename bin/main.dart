import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:crypto/crypto.dart';
import 'package:guildserver/handlers/race_handler.dart';
import 'package:guildserver/handlers/unit_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:guildserver/utils/timezone_config_utils.dart';
import 'package:guildserver/db/db.dart';
import 'package:guildserver/services/resources_tick_service.dart';
import 'package:guildserver/middleware/auth_middleware.dart';

import 'package:guildserver/handlers/admin_users_handler.dart';
import 'package:guildserver/handlers/admin_connected_handler.dart';
import 'package:guildserver/handlers/admin_race_stats_handler.dart';
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
import '../lib/handlers/auth_handler.dart';

Future<void> main() async {
  // Carga de variables de entorno y configuración de zona horaria
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final timezone = env['TZ'] ?? 'America/Argentina/Buenos_Aires';
  configureTimezone(timezone);

  // Inicializar conexión a BD
  await initDb(env);

  // Iniciar servicio de ticks de recursos
  ResourceTickService().start();

  // Rutas públicas (no requieren token)
  final publicRoutes = Router()
    ..post('/auth/register', registerHandler)
    ..post('/auth/login', loginHandler)
    ..get('/guild/list', listGuildsHandler)
    ..get('/guild/ranking', guildRankingHandler)
    ..get('/guild/image/<guildId>', getGuildImageHandler)
    ..get('/chat/global/history', chatGlobalHistoryHandler)
    ..get('/ranking', rankingHandler)
    ..get('/online_users', onlineUsersHandler)
  ..get ('/race/list',     raceListHandler)  // ← NUEVA
..get('/unit/list', unitListHandler);
  // Rutas de administración (sin auth)
  final adminRoutes = Router()
    ..get('/admin/users', adminUsersHandler)
    ..get('/admin/connected_users', adminConnectedUsersHandler)
    ..get('/admin/server_time', serverTimeHandler)
    ..get('/admin/raza_stats', adminRazaStatsHandler);

  // Rutas protegidas (requieren token en headers)
  final protectedRoutes = Router()
    ..post('/user/update_fcm', updateFcmTokenHandler)
    ..post('/user/profile', getUserProfile)
    ..post('/user/collect', collectResourcesHandler)
    ..post('/build/cancel', cancelConstruction)
    ..post('/build/start', startConstruction)
    ..post('/build/status', checkConstructionStatus)
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

  // Servir archivos estáticos de la carpeta `web/`
  final staticHandler = createStaticHandler('web', defaultDocument: 'index.html');

  // Componer cascade de handlers:
  // 1) Favicon
  // 2) Estáticos (HTML/CSS/JS)
  // 3) Admin (sin auth)
  // 4) Protegidas (con auth)
  // 5) Públicas
  final handler = Cascade()
      .add((Request req) {
        if (req.url.path == 'favicon.ico') {
          final file = File('web/favicon.ico');
          if (!file.existsSync()) return Response.notFound('');
          return Response.ok(
            file.readAsBytesSync(),
            headers: {'Content-Type': 'image/x-icon'},
          );
        }
        return Response.notFound('');
      })
      .add(staticHandler)
      .add(adminRoutes)


        .add(publicRoutes)
      .add(authMiddleware()(protectedRoutes))

      .handler;

  // Pipeline con logging y CORS
  final pipeline = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware((inner) {
        return (Request req) async {
          final resp = await inner(req);
          return resp.change(headers: {
            ...resp.headers,
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'uid,token,Content-Type',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
          });
        };
      })
      .addHandler(handler);

  // Levantar servidor
  final server = await serve(pipeline, InternetAddress.anyIPv4, 8080);
  print('Servidor iniciado en http://${server.address.host}:${server.port}');
}

// Handler para devolver hora del servidor en ISO8601
Response serverTimeHandler(Request request) {
  final now = tz.TZDateTime.now(tz.local);
  return Response.ok(jsonEncode({
    'server_time': now.toIso8601String(),
  }));
}
