import 'dart:convert';
import 'dart:math';

class GameManager {
  final Map<String, GameRoom> rooms = {};
  final Map<String, Game> games = {};

  GameManager() { print('GameManager initialized'); }

  String createRoom() {
    final code = Random().nextInt(999999).toString().padLeft(6, '0');
    rooms[code] = GameRoom(code: code);
    print('Room created: $code');
    return code;
  }

  Map<String, dynamic> createTemplate() {
    final prices = [
      [100, 200, 300, 400, 500],
      [200, 400, 600, 800, 1000],
      [300, 600, 900, 1200, 1500],
    ];
    final rounds = <Map<String, dynamic>>[];
    for (int r = 0; r < 3; r++) {
      final categories = <Map<String, dynamic>>[];
      for (int c = 0; c < 5; c++) {
        final questions = <Map<String, dynamic>>[];
        for (final price in prices[r]) {
          questions.add({'price': price, 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''});
        }
        categories.add({'name': 'Theme ${c + 1}', 'questions': questions});
      }
      rounds.add({'name': 'Round ${r + 1}', 'categories': categories});
    }
    final finalThemes = List.generate(10, (i) => {'name': 'Theme ${i + 1}', 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''});
    return {'rounds': rounds, 'final': finalThemes};
  }

  void saveTemplate(String roomCode, Map<String, dynamic> template) {
    rooms[roomCode]?.template = template;
  }

  void startGame(String roomCode, String playerId) {
    final room = rooms[roomCode];
    if (room == null || room.creator != playerId) return;
    final game = _createGame(room);
    games[roomCode] = game;
    room.status = 'playing';
    _broadcastGameState(roomCode);
  }

  Game _createGame(GameRoom room) {
    return Game(
      roomCode: room.code,
      template: room.template ?? {},
      players: room.players,
    );
  }

  void _broadcastGameState(String roomCode) {
    final room = rooms[roomCode];
    final game = games[roomCode];
    if (room == null || game == null) return;

    final state = jsonEncode({
      'type': 'game_state',
      'game': game.toJson(),
      'players': room.playersJson(),
      'host_name': room.hostName,
    });

    for (final player in room.players.values) {
      player.sink?.add(state);
    }
  }

  void handleMessage(String roomCode, String playerId, String data) {
    final msg = jsonDecode(data) as Map<String, dynamic>;
    final type = msg['type'] as String?;
    final room = rooms[roomCode];
    final game = games[roomCode];

    switch (type) {
      case 'join':
        room?.players[playerId]?.name = msg['name'] ?? 'Player';
        _broadcastRoomState(roomCode);
        break;
      case 'set_creator':
        room?.creator = playerId;
        room?.hostName = room?.players[playerId]?.name ?? 'Host';
        _broadcastRoomState(roomCode);
        break;
      case 'start_game':
        startGame(roomCode, playerId);
        break;
    }
  }

  void _broadcastRoomState(String roomCode) {
    final room = rooms[roomCode];
    if (room == null) return;

    final state = jsonEncode({
      'type': 'room_state',
      'status': room.status,
      'players': room.playersJson(),
      'players_count': room.players.values.where((p) => p.name != null).length,
      'max_players': 5,
      'creator': room.creator,
      'host': room.creator,
      'host_name': room.hostName,
    });

    for (final player in room.players.values) {
      player.sink?.add(state);
    }
  }
}

class GameRoom {
  final String code;
  String status = 'waiting';
  String? creator;
  String? hostName;
  Map<String, dynamic>? template;
  final Map<String, Player> players = {};

  GameRoom({required this.code});

  Map<String, dynamic> playersJson() {
    final json = <String, dynamic>{};
    for (final entry in players.entries) {
      json[entry.key] = {'name': entry.value.name, 'score': entry.value.score, 'is_host': false};
    }
    return json;
  }
}

class Player {
  String? name;
  int score = 0;
  dynamic sink; // WebSocket sink
  bool canAnswer = false;

  Player({this.name, this.sink});
}

class Game {
  final String roomCode;
  final Map<String, dynamic> template;
  final Map<String, Player> players;
  int currentRound = 0;
  Map<String, dynamic>? currentQuestion;
  List<String> answeredPlayers = [];
  String phase = 'playing';
  String? answeringName;

  Game({required this.roomCode, required this.template, required this.players});

  Map<String, dynamic> toJson() => {
        'current_round': currentRound,
        'current_question': currentQuestion,
        'phase': phase,
        'answering_name': answeringName,
        'rounds': template['rounds'] ?? [],
        'final': template['final'] ?? [],
      };
}
