import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

class GameService extends ChangeNotifier {
  WebSocketChannel? _channel;
  String? _playerId;
  String? _roomCode;
  Map<String, dynamic> _roomState = {};
  Map<String, dynamic> _gameState = {};
  bool _isConnected = false;
  final String _serverUrl = 'ws://localhost:8000/ws';

  // Getters
  String? get playerId => _playerId;
  String? get roomCode => _roomCode;
  Map<String, dynamic> get roomState => _roomState;
  Map<String, dynamic> get gameState => _gameState;
  bool get isConnected => _isConnected;
  bool get isHost => _roomState['host'] == _playerId;
  int get playerCount => (_roomState['players'] as Map?)?.length ?? 0;

  Future<void> connectToRoom(String roomCode, String playerName) async {
    _playerId = const Uuid().v4();
    _roomCode = roomCode;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$_serverUrl/$roomCode/$_playerId'),
      );

      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'room_state') {
            _roomState = data;
          } else if (data['type'] == 'game_state') {
            _gameState = data;
          }
          notifyListeners();
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          _isConnected = false;
          notifyListeners();
        },
      );

      sendMessage({'type': 'join', 'name': playerName});
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  // Game actions
  void setCreator() => sendMessage({'type': 'set_creator'});
  void startGame() => sendMessage({'type': 'start_game'});
  
  void selectQuestion(String category, int price) {
    sendMessage({
      'type': 'select_question',
      'category': category,
      'price': price,
    });
  }

  void attemptAnswer() => sendMessage({'type': 'answer_attempt'});
  
  void evaluateAnswer(bool correct) {
    sendMessage({'type': 'evaluate_answer', 'correct': correct});
  }

  void openQuestion() => sendMessage({'type': 'open_question'});
  void skipQuestion() => sendMessage({'type': 'skip_question'});

  void placeFinalBet(int bet) {
    sendMessage({'type': 'final_bet', 'bet': bet});
  }

  void submitFinalAnswer(String answer) {
    sendMessage({'type': 'final_answer', 'answer': answer});
  }

  void evaluateFinal(Map<String, bool> results) {
    sendMessage({'type': 'evaluate_final', 'results': results});
  }

  void eliminateTheme(String theme) {
    sendMessage({'type': 'eliminate_theme', 'theme': theme});
  }

  void saveGame() => sendMessage({'type': 'save_game'});

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}
