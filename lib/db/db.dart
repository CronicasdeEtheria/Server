import 'package:mysql_client/mysql_client.dart';
import 'package:dotenv/dotenv.dart';

late MySQLConnectionPool connectionPool;

Future<void> initDb(DotEnv env) async {
  connectionPool = MySQLConnectionPool(
    host: env['DB_HOST']!,
    port: int.parse(env['DB_PORT']!),
    userName: env['DB_USER']!,
    password: env['DB_PASSWORD'],
    databaseName: env['DB_NAME'],
    maxConnections: 10,
    secure: false, // Ajusta según tu configuración
  );

  print('✅ Pool de conexiones MySQL inicializado.');
}

Future<MySQLConnectionPool> getConnection() async {
  print('🔌 [DB] Solicitando conexión MySQL...');
  return connectionPool;
}
