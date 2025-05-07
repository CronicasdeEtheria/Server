// guildserver/lib/handlers/race_handler.dart
import 'dart:convert';
import 'package:guildserver/catalog/race_catalog.dart';
import 'package:shelf/shelf.dart';

Response raceListHandler(Request _) {
  final json = kRaces.map((r) => r.toJson()).toList();
  return Response.ok(jsonEncode(json), headers: {'Content-Type': 'application/json'});
}
