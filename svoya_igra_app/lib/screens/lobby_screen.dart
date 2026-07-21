import "game_screen.dart";
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String roomCode;
  final String hostName;
  final Map<String, dynamic> template;
  const LobbyScreen({super.key, required this.roomCode, required this.hostName, required this.template});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  WebSocketChannel? _channel;
  final List<String> _playerNames = [];
  bool _joined = false;
  final _streamController = StreamController<dynamic>.broadcast();
  StreamSubscription? _subscription;

  @override
  void initState() { super.initState(); _connect(); }

  void _connect() {
    final pid = Random().nextInt(999999).toString().padLeft(6, '0');
    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8000/ws/${widget.roomCode}/$pid'));
    _subscription = _channel!.stream.listen((data) {
      _streamController.add(data);
      _onMsg(data);
    });
    _channel!.sink.add(jsonEncode({'type': 'join', 'name': widget.hostName}));
  }

  void _onMsg(dynamic data) {
    final msg = jsonDecode(data);
    if (msg['type'] == 'room_state') {
      if (!_joined) { _channel!.sink.add(jsonEncode({'type': 'set_creator'})); _joined = true; return; }
      final players = msg['players'];
      if (players is Map) {
        setState(() {
          _playerNames.clear();
          for (final p in players.values) {
            if (p is Map && p['is_host'] != true) _playerNames.add((p['name'] ?? 'Player').toString());
          }
        });
      }
    } else if (msg['type'] == 'game_state') {
      _subscription?.cancel();
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => GameScreen(roomCode: widget.roomCode, hostName: widget.hostName, gameState: msg),
      ));
    }
  }

  @override
  void dispose() { super.dispose(); }

  void _startGame() => _channel?.sink.add(jsonEncode({'type': 'start_game'}));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Room: ${widget.roomCode}', style: const TextStyle(fontSize: 32, letterSpacing: 4)),
        const SizedBox(height: 20),
        Text('Players (${_playerNames.length}/5):', style: const TextStyle(fontSize: 18)),
        ..._playerNames.map((n) => Text(n, style: const TextStyle(fontSize: 16))),
        const SizedBox(height: 30),
        ElevatedButton(onPressed: _startGame, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)), child: const Text('START GAME', style: TextStyle(fontSize: 20))),
      ])),
    );
  }
}
