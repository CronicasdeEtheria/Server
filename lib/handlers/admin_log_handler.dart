// lib/handlers/log_handler.dart
import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Devuelve las últimas 100 líneas (o menos) del fichero de log
Future<Response> adminLogHandler(Request req) async {
  // Ruta configurable vía env LOG_PATH, o 'logs/server.log' por defecto
  final logPath = Platform.environment['LOG_PATH'] ?? 'logs/server.log';

  try {
    final file = File(logPath);
    if (!await file.exists()) {
      return Response.notFound(
        jsonEncode({'error': 'Log file not found at $logPath'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Leemos todas las líneas y tomamos las últimas 100
    final allLines = await file.readAsLines();
    final start = allLines.length > 100 ? allLines.length - 100 : 0;
    final lastLines = allLines.sublist(start);

    return Response.ok(
      jsonEncode({'lines': lastLines}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error reading log', 'details': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
