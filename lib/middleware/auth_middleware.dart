import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final uid = request.headers['uid'];
      final token = request.headers['token'];

      if (uid == null || token == null) {
        return Response.forbidden('Faltan encabezados de autenticación.');
      }

      try {
        final pool = await getConnection();
        final result = await pool.execute(
          '''
          SELECT id
            FROM users
           WHERE id = :uid
             AND session_token = :token
          ''',
          {
            'uid': uid,
            'token': token,
          },
        );

        if (result.rows.isEmpty) {
          return Response.forbidden('Token inválido o sesión expirada.');
        }

        return await innerHandler(request);
      } catch (e, st) {
        print('❌ Error en authMiddleware: $e');
        print(st);
        return Response.internalServerError(
          body: 'Error de autenticación interno.',
        );
      }
    };
  };
}
