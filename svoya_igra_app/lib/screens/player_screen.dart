import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:math';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  WebSocketChannel? _channel;
  String _screen = 'login';
  String _status = '';
  String _roomCode = '';
  int _myScore = 0;
  int _playerCount = 0;
  bool _canAnswer = false;
  bool _isFinal = false;
  String _finalPhase = '';
  bool _hasBet = false;
  bool _hasAnswered = false;
  final _betCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  @override
  void dispose() {
    _channel?.sink.close();
    _roomCtrl.dispose(); _nameCtrl.dispose();
    _betCtrl.dispose(); _answerCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final room = _roomCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (room.isEmpty || name.isEmpty) return;
    final playerId = Random().nextInt(999999).toString().padLeft(6, '0');
    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8000/ws/$room/$playerId'));
    _channel!.stream.listen(_onMessage);
    _channel!.sink.add(jsonEncode({'type': 'join', 'name': name}));
    setState(() { _roomCode = room; _screen = 'waiting'; });
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data);
    if (msg['type'] == 'room_state') {
      setState(() => _playerCount = msg['players_count'] ?? 0);
    } else if (msg['type'] == 'game_state') {
      final players = msg['players'] as Map<String, dynamic>? ?? {};
      final game = msg['game'] as Map<String, dynamic>? ?? {};
      final me = (players.values.firstWhere((p) => p is Map, orElse: () => null) as Map<String, dynamic>?);
      if (me == null) return;
      setState(() {
        _screen = 'game';
        _myScore = me['score'] ?? 0;
        _hasBet = me['has_bet'] ?? false;
        _hasAnswered = me['has_answered'] ?? false;
        final phase = game['phase'] ?? '';
        final fp = game['final_phase'] ?? '';
        _isFinal = phase == 'final' && fp.isNotEmpty;
        _finalPhase = fp;
        final q = game['current_question'] as Map<String, dynamic>?;
        if (!_isFinal && q != null) {
          final st = q['status'] ?? '';
          _canAnswer = st == 'open' && (me['can_answer'] == true);
          _status = _canAnswer ? 'PRESS TO ANSWER!' : st == 'selected' ? 'Host is reading...' : 'Waiting...';
        }
      });
    }
  }

  void _answer() {
    _channel?.sink.add(jsonEncode({'type': 'answer_attempt'}));
    setState(() { _canAnswer = false; _status = 'Answer sent!'; });
  }

  void _placeBet() {
    final bet = int.tryParse(_betCtrl.text) ?? 0;
    if (bet < 0 || bet > _myScore) return;
    _channel?.sink.add(jsonEncode({'type': 'final_bet', 'bet': bet}));
    setState(() { _hasBet = true; _status = 'Bet placed!'; });
  }

  void _submitAnswer() {
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) return;
    _channel?.sink.add(jsonEncode({'type': 'final_answer', 'answer': ans}));
    setState(() { _hasAnswered = true; _status = 'Answer submitted!'; });
  }

  @override
  Widget build(BuildContext context) {
    if (_screen == 'login') {
      return Scaffold(body: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Join Game', style: TextStyle(fontSize: 32)), const SizedBox(height: 20),
        TextField(controller: _roomCtrl, decoration: const InputDecoration(labelText: 'Room code'), textCapitalization: TextCapitalization.characters),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 20), ElevatedButton(onPressed: _connect, child: const Text('Join')),
      ])));
    }
    if (_screen == 'waiting') {
      return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Waiting for game...', style: TextStyle(fontSize: 24)),
        Text('Room: $_roomCode'), Text('Players: $_playerCount/5'),
      ])));
    }
    return Scaffold(body: SafeArea(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('$_myScore', style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: _myScore >= 0 ? Colors.green : Colors.red)),
      Text(_status, style: const TextStyle(fontSize: 22)), const SizedBox(height: 30),
      if (_isFinal && _finalPhase == 'betting' && !_hasBet) ...[
        Text('Max bet: $_myScore'),
        TextField(controller: _betCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center),
        ElevatedButton(onPressed: _placeBet, child: const Text('SUBMIT BET')),
      ],
      if (_isFinal && _finalPhase == 'answering' && !_hasAnswered) ...[
        TextField(controller: _answerCtrl, decoration: const InputDecoration(hintText: 'Your answer')),
        ElevatedButton(onPressed: _submitAnswer, child: const Text('SUBMIT ANSWER')),
      ],
      if (!_isFinal) ...[
        GestureDetector(
          onTap: _canAnswer ? _answer : null,
          child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _canAnswer ? Colors.green : Colors.grey),
            child: const Center(child: Text('ANSWER', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
          ),
        ),
      ],
    ])));
  }
}
