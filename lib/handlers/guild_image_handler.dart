import 'dart:convert';
import 'dart:io';
import 'package:guildserver/db/db.dart';
import 'package:shelf/shelf.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:mysql_client/mysql_client.dart';

final _uuid = Uuid();

Future<Response> uploadGuildImageHandler(Request request) async {
  // 1️⃣ Validación de content-type
  final contentType = request.headers['content-type'];
  if (contentType == null || !contentType.contains('multipart/form-data')) {
    return Response(400, body: 'Formato no soportado. Usar multipart/form-data.');
  }

  // 2️⃣ Extraer boundary
  final boundary = contentType.split('boundary=').last;
  final transformer = MimeMultipartTransformer(boundary);

  // 3️⃣ Obtener el pool
  final pool = await getConnection();

  // 4️⃣ Parsear las partes
  String? guildId;
  File? imageFile;
  final bodyStream = request.read();
  final parts = await transformer.bind(bodyStream).toList();

  for (final part in parts) {
    final disposition = part.headers['content-disposition'];
    if (disposition == null) continue;

    final nameMatch     = RegExp(r'name="([^"]+)"').firstMatch(disposition);
    final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
    final fieldName     = nameMatch?.group(1);
    if (fieldName == null) continue;

    // Leer TODOS los bytes de la parte
    final rawBytes = await part.fold<List<int>>([], (buf, chunk) => buf..addAll(chunk));

    if (fieldName == 'guild_id') {
      // Texto
      guildId = utf8.decode(rawBytes).trim();
    }

    else if (fieldName == 'image' && filenameMatch != null && guildId != null) {
      // Imagen
      final originalName = filenameMatch.group(1)!;
      final ext = p.extension(originalName).toLowerCase();
      if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') {
        return Response(400, body: 'Solo imágenes .jpg o .png permitidas.');
      }

      // Guardar siempre como JPG
      final dirPath = Directory('storage/guilds');
      if (!await dirPath.exists()) await dirPath.create(recursive: true);
      final filePath = 'storage/guilds/$guildId.jpg';
      final file = File(filePath);
      await file.writeAsBytes(rawBytes);
      imageFile = file;

      // Actualizar en DB
      await pool.execute(
        'UPDATE guilds SET image_url = :url WHERE id = :id',
        {
          'url': filePath,
          'id': guildId,
        },
      );
    }
  }

  if (guildId == null || imageFile == null) {
    return Response(400, body: 'Faltan parámetros o imagen.');
  }

  return Response.ok(jsonEncode({
    'status': 'uploaded',
    'path': imageFile.path,
  }));
}

Future<Response> getGuildImageHandler(Request request, String guildId) async {
  // 1) Intentamos la imagen subida/copied
  final storagePath = 'storage/guilds/$guildId.jpg';
  File file = File(storagePath);

  // 2) Si no existe, usamos un fallback genérico en assets
  if (!await file.exists()) {
    final fallback = File('assets/guild_icons/default.png');
    if (!await fallback.exists()) {
      // Ni la fallback está: 404
      return Response.notFound('Imagen no encontrada.');
    }
    file = fallback;
  }

  // 3) Detectamos MIME y devolvemos bytes
  final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
  final bytes = await file.readAsBytes();
  return Response.ok(bytes, headers: {
    'Content-Type': mimeType,
    'Cache-Control': 'public, max-age=86400',
  });
}