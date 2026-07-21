import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'game_manager.dart';

class SvoyaServer {
  final GameManager gameManager = GameManager();
  late HttpServer _server;
  int port = 8000;

  Future<void> start() async {
    final router = Router();

    router.get('/', (request) => Response.ok('Svoya Igra Server'));
    router.get('/health', (request) => Response.ok('{"status":"ok"}'));
    router.post('/api/create_room', (request) {
      final code = gameManager.createRoom();
      return Response.ok('{"room_code":"$code","status":"created"}');
    });
    router.get('/api/template', (request) {
      return Response.ok(jsonEncode(gameManager.createTemplate()));
    });

    // WebSocket
    router.get('/ws/<roomCode>/<playerId>', (request, String roomCode, String playerId) {
      final room = gameManager.rooms[roomCode];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (room != null) {
          room.players[playerId] = Player(name: 'Player...', sink: channel.sink);
        }
        channel.stream.listen((data) {
          gameManager.handleMessage(roomCode, playerId, data as String);
        }, onDone: () {
          room?.players.remove(playerId);
        });
      })(request);
    });

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    print('Server running on http://0.0.0.0:$port');
  }

  void stop() {
    _server.close();
  }
}
