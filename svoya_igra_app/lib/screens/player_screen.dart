import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:html' as html;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  html.WebSocket? _ws;
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
  String _serverHost = 'localhost';

  @override
  void initState() {
    super.initState();
    final host = html.window.location.hostname ?? "";
    _serverHost = host.isNotEmpty ? host : 'localhost';
  }

  @override
  void dispose() {
    _ws?.close();
    _roomCtrl.dispose(); _nameCtrl.dispose();
    _betCtrl.dispose(); _answerCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final room = _roomCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (room.isEmpty || name.isEmpty) {
      setState(() => _status = 'Enter code and name');
      return;
    }
    final pid = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
    final url = 'ws://$_serverHost:8000/ws/$room/$pid';
    _ws = html.WebSocket(url);
    _ws!.onOpen.first.then((_) => _ws!.send(jsonEncode({'type': 'join', 'name': name})));
    _ws!.onMessage.listen((event) {
      final msg = jsonDecode(event.data.toString());
      if (msg['type'] == 'room_state') {
        setState(() { _screen = 'waiting'; _roomCode = room; _playerCount = msg['players_count'] ?? 0; });
      } else if (msg['type'] == 'game_state') {
        _updateGame(msg);
      }
    });
    setState(() { _roomCode = room; _screen = 'waiting'; });
  }

  void _updateGame(Map<String, dynamic> msg) {
    final players = msg['players'] as Map<String, dynamic>? ?? {};
    final game = msg['game'] as Map<String, dynamic>? ?? {};
    Map<String, dynamic>? me;
    for (final p in players.values) {
      if (p is Map<String, dynamic>) { me = p; break; }
    }
    if (me == null) return;

    setState(() {
      _screen = 'game';
      _myScore = (me?['score'] as int?) ?? 0;
      _hasBet = (me?['has_bet'] as bool?) ?? false;
      _hasAnswered = (me?['has_answered'] as bool?) ?? false;
      final phase = game['phase'] ?? '';
      final fp = game['final_phase'] ?? '';
      _isFinal = phase == 'final' && fp.isNotEmpty;
      _finalPhase = fp;
      final q = game['current_question'] as Map<String, dynamic>?;
      if (!_isFinal && q != null) {
        final st = q['status'] ?? '';
        _canAnswer = st == 'open' && (me?['can_answer'] == true);
        _status = _canAnswer ? 'PRESS TO ANSWER!' : st == 'selected' ? 'Host is reading...' : 'Waiting...';
      } else if (_isFinal) {
        _status = fp == 'betting' ? 'Place your bet (max: $_myScore)' : fp == 'answering' ? 'Enter your answer' : 'Waiting for results...';
      }
    });
  }

  void _send(String type, [Map<String, dynamic>? extra]) {
    final msg = <String, dynamic>{'type': type};
    if (extra != null) msg.addAll(extra);
    _ws?.send(jsonEncode(msg));
  }

  void _answer() => _send('answer_attempt');
  void _placeBet() {
    final bet = int.tryParse(_betCtrl.text) ?? 0;
    if (bet < 0 || bet > _myScore) return;
    _send('final_bet', {'bet': bet});
    setState(() { _hasBet = true; });
  }
  void _submitAnswer() {
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) return;
    _send('final_answer', {'answer': ans});
    setState(() { _hasAnswered = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_screen == 'login') {
      return Scaffold(body: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Join Game', style: TextStyle(fontSize: 32)), const SizedBox(height: 20),
        Text('Server: $_serverHost', style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 10),
        TextField(controller: _roomCtrl, decoration: const InputDecoration(labelText: 'Room code'), textCapitalization: TextCapitalization.characters),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Your name')),
        if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_status, style: const TextStyle(color: Colors.red))),
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
      const SizedBox(height: 15),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _canAnswer ? Colors.green : Colors.grey[800], borderRadius: BorderRadius.circular(10)),
        child: Text(_status, style: const TextStyle(fontSize: 20))),
      const SizedBox(height: 25),
      if (_isFinal && _finalPhase == 'betting' && !_hasBet) ...[
        TextField(controller: _betCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'Your bet')),
        const SizedBox(height: 10), ElevatedButton(onPressed: _placeBet, child: const Text('SUBMIT BET')),
      ],
      if (_isFinal && _finalPhase == 'answering' && !_hasAnswered) ...[
        TextField(controller: _answerCtrl, decoration: const InputDecoration(hintText: 'Your answer')),
        const SizedBox(height: 10), ElevatedButton(onPressed: _submitAnswer, child: const Text('SUBMIT ANSWER')),
      ],
      if (!_isFinal) ...[
        GestureDetector(
          onTap: _canAnswer ? _answer : null,
          child: Container(width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _canAnswer ? Colors.green : Colors.grey[700],
              boxShadow: _canAnswer ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 30)] : []),
            child: const Center(child: Text('ANSWER', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
          ),
        ),
      ],
    ])));
  }
}
