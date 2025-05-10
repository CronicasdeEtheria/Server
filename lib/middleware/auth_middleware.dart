// lib/middleware/auth_middleware.dart

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:guildserver/db/db.dart';

/// Middleware que valida uid y token en headers,
/// y agrega userId al context para handlers.
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      // Bypass GET de imágenes de gremio (ruta pública)
      if (request.method == 'GET' &&
          request.url.pathSegments.length == 3 &&
          request.url.pathSegments[0] == 'guild' &&
          request.url.pathSegments[1] == 'image') {
        return await innerHandler(request);
      }

      final uid = request.headers['uid'];
      final token = request.headers['token'];

      if (uid == null || token == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Faltan encabezados de autenticación.'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      try {
        final pool = await getConnection();
        final result = await pool.execute(
          '''
          SELECT id
            FROM users
           WHERE id = :uid
             AND session_token = :token
          ''' ,
          {'uid': uid, 'token': token},
        );

        if (result.rows.isEmpty) {
          return Response.forbidden(
            jsonEncode({'error': 'Token inválido o sesión expirada.'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Inyectar userId en el context para handlers protegidos
        final updatedRequest = request.change(context: {'userId': uid});
        return await innerHandler(updatedRequest);
      } catch (e, st) {
        print('❌ Error en authMiddleware: \$e');
        print(st);
        return Response.internalServerError(
          body: jsonEncode({'error': 'Error de autenticación interno.'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
