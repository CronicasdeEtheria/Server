import 'dart:io';

class ConnectionManager {
  final Map<String, WebSocket> _connections = {}; // uid → socket
List<WebSocket> get connectedSockets => _connections.values.toList();

  void add(String uid, WebSocket socket) {
    _connections[uid] = socket;
  }

  void remove(String uid) {
    _connections.remove(uid);
  }

  List<String> get connectedUids => _connections.keys.toList();

  bool isOnline(String uid) => _connections.containsKey(uid);
}

final connectionManager = ConnectionManager();
