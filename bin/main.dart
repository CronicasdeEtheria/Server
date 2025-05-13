import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:guildserver/handlers/admin_log_handler.dart';
import 'package:guildserver/handlers/race_handler.dart';
import 'package:guildserver/handlers/unit_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:logging/logging.dart';
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
import 'package:guildserver/handlers/auth_handler.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();
  final timezone = env['TZ'] ?? 'America/Argentina/Buenos_Aires';
  configureTimezone(timezone);
  await initDb(env);
  ResourceTickService().start();

  final logPath = env['LOG_PATH'] ?? 'logs/server.log';
  final logFile = File(logPath);
  final logSink = logFile.openWrite(mode: FileMode.append);
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final time = record.time.toIso8601String().substring(0, 16);
    final msg = '$time [${record.level.name}] ${record.loggerName}: ${record.message}';
    logSink.writeln(msg);
    stdout.writeln(msg);
  });

  final publicRoutes = Router()
    ..post('/auth/register', registerHandler)
    ..post('/auth/login', loginHandler)
    ..get('/guild/list', listGuildsHandler)
    ..get('/guild/ranking', guildRankingHandler)
    ..get('/guild/image/<guildId>', getGuildImageHandler)
    ..get('/chat/global/history', chatGlobalHistoryHandler)
    ..get('/ranking', rankingHandler)
    ..get('/online_users', onlineUsersHandler)
    ..get('/race/list', raceListHandler)
    ..get('/unit/list', unitListHandler)
    ..post('/guild/upload_image', uploadGuildImageHandler)
    ..get('/ws/log', logWebSocketHandler);

  final adminRoutes = Router()
    ..get('/admin/users', adminUsersHandler)
    ..get('/admin/connected_users', adminConnectedUsersHandler)
    ..get('/admin/server_time', serverTimeHandler)
    ..get('/admin/raza_stats', adminRazaStatsHandler)
    ..post('/admin/restart', adminRestartHandler)
    ..post('/admin/broadcast', adminBroadcastHandler);

  final protectedRoutes = Router()
    ..post('/battle/army', battleArmyHandler)
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
    ..post('/guild/kick_member', kickMemberHandler)
    ..post('/guild/transfer_leadership', transferLeadershipHandler)
    ..post('/guild/update_info', updateGuildInfoHandler)
    ..post('/user/stats', getUserStatsHandler)
    ..post('/user/battle_stats', getUserBattleStatsHandler)
    ..post('/chat/global/send', chatGlobalSendHandler);

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
      .add(publicRoutes)
      .add(adminRoutes)
      .add(createStaticHandler('web', defaultDocument: 'index.html'))
      .add(authMiddleware()(protectedRoutes))
      .handler;

  final pipeline = Pipeline()
      .addMiddleware((inner) {
        final logger = Logger('HTTP');
        return (Request req) async {
          logger.info('→ ${req.method} ${req.requestedUri}');
          final resp = await inner(req);
          logger.info('← ${resp.statusCode} ${req.method} ${req.requestedUri}');
          return resp;
        };
      })
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

  final port = int.parse(env['PORT'] ?? '8081');
  final server = await serve(pipeline, InternetAddress.anyIPv4, port);
  print('Servidor iniciado en http://${server.address.host}:${server.port}');
}

Response serverTimeHandler(Request request) {
  final now = tz.TZDateTime.now(tz.local);
  return Response.ok(jsonEncode({'server_time': now.toIso8601String()}));
}
