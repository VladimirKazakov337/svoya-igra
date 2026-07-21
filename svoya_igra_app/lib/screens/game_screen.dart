import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:html' as html;

class GameScreen extends StatefulWidget {
  final String roomCode;
  final String hostName;
  final Map<String, dynamic> gameState;
  const GameScreen({super.key, required this.roomCode, required this.hostName, required this.gameState});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Map<String, dynamic> _game = {};
  List<Map<String, dynamic>> _players = [];
  int _currentRound = 0;
  Map<String, dynamic>? _question;
  bool _showAnswer = false;
  html.WebSocket? _ws;

  @override
  void initState() {
    super.initState();
    _updateState(widget.gameState);
    final pid = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
    _ws = html.WebSocket('ws://localhost:8000/ws/${widget.roomCode}/$pid');
    _ws!.onOpen.first.then((_) {
      _ws!.send(jsonEncode({'type': 'join', 'name': widget.hostName}));
      _ws!.send(jsonEncode({'type': 'set_creator'}));
    });
    _ws!.onMessage.listen((event) {
      final msg = jsonDecode(event.data.toString());
      if (msg['type'] == 'game_state') _updateState(msg);
    });
  }

  void _updateState(Map<String, dynamic> msg) {
    final game = msg['game']; final players = msg['players'];
    setState(() {
      _game = (game is Map<String, dynamic>) ? game : {};
      _players = [];
      if (players is Map) {
        for (final p in players.values) {
          if (p is Map<String, dynamic> && p['is_host'] != true) _players.add(p);
        }
      }
      _currentRound = _game['current_round'] ?? 0;
      _question = _game['current_question'];
      _showAnswer = false;
    });
  }

  void _send(String type, [Map<String, dynamic>? extra]) {
    final msg = <String, dynamic>{'type': type};
    if (extra != null) msg.addAll(extra);
    _ws?.send(jsonEncode(msg));
  }

  void _select(String cat, int price) => _send('select_question', {'category': cat, 'price': price});
  void _activate() => _send('open_question');
  void _eval(bool c) => _send('evaluate_answer', {'correct': c});
  void _skip() { _send('skip_question'); }
  void _next() => _send('next_round');
  void _skipToFinal() => _send('skip_to_final');

  @override
  void dispose() { _ws?.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final round = (_game['rounds'] as List?)?.elementAt(_currentRound) ?? {};
    final cats = (round['categories'] as List?)?.map((c) => c.toString()).toList() ?? [];
    final prices = (round['prices'] as List?)?.map((p) => p is int ? p : int.tryParse('$p') ?? 0).toList() ?? [];
    final questions = (round['questions'] as Map?) ?? {};
    final q = _question;

    return Scaffold(
      body: SafeArea(child: Stack(children: [
        Column(children: [
          Container(padding: const EdgeInsets.all(8), color: const Color(0xFF0A0A1E),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${round['name'] ?? 'Round'} (${_currentRound + 1}/3)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Host: ${widget.hostName}', style: const TextStyle(fontSize: 13)),
            ]),
          ),
          if (_players.isNotEmpty) SizedBox(height: 45, child: ListView(scrollDirection: Axis.horizontal, children: _players.map((p) {
            final score = p['score'] ?? 0;
            return Container(margin: const EdgeInsets.all(3), padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFF2A2A4A), borderRadius: BorderRadius.circular(6)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(p['name']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                Text('$score', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: score >= 0 ? Colors.green : Colors.red)),
              ]));
          }).toList())),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(3),
            child: Column(children: [
              Row(children: cats.map((c) => Expanded(child: Container(
                height: 32, alignment: Alignment.center, color: Colors.orange, margin: const EdgeInsets.all(1),
                child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
              ))).toList()),
              ...prices.map((price) => Row(children: cats.map((cat) {
                final key = '$cat\_$price';
                final exists = questions.containsKey(key);
                final sel = q != null && q['category'] == cat && q['price'] == price;
                return Expanded(child: Padding(padding: const EdgeInsets.all(1), child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: sel ? Colors.orange : (exists ? Colors.blue : Colors.grey[800]),
                    padding: EdgeInsets.zero, minimumSize: const Size(30, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: (exists && q == null) ? () => _select(cat, price) : null,
                  child: exists ? Text('$price', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)) : null,
                )));
              }).toList())),
            ]),
          )),
          Container(padding: const EdgeInsets.all(6), color: const Color(0xFF1A1A3E), height: 45,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_game['answering_name'] != null && _game['answering_name'] != '')
                Text('ANSWERING: ${_game['answering_name']}', style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton(onPressed: _skipToFinal, child: const Text('Skip to Final', style: TextStyle(fontSize: 11))),
              if (q == null && questions.isEmpty) ElevatedButton(onPressed: _next, child: const Text('Next Round', style: TextStyle(fontSize: 11))),
            ]),
          ),
        ]),
        // Fullscreen overlay
        if (q != null)
          GestureDetector(
            onTap: () {}, // blocks taps behind
            child: Container(
              color: Colors.black.withOpacity(0.95),
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    margin: const EdgeInsets.all(25),
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Question text
                      Text(q['question']?['text'] ?? 'Question', style: const TextStyle(fontSize: 24, color: Colors.white)),
                      const SizedBox(height: 15),
                      // Media
                      if (q['question']?['qmedia'] != null && q['question']?['qmedia'] != '')
                        Image.network(q['question']['qmedia'], height: 200, fit: BoxFit.contain),
                      const SizedBox(height: 15),
                      // Answer (if shown)
                      if (_showAnswer && q['question']?['answer'] != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('ANSWER: ${q['question']['answer']}', style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 15),
                      // Answerer
                      if (_game['answering_name'] != null && _game['answering_name'] != '')
                        Text('ANSWERING: ${_game['answering_name']}', style: const TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      // Buttons
                      Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                        if (q['status'] == 'selected' || q['status'] == 'open')
                          ElevatedButton(onPressed: _activate, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('ACTIVATE ANSWER', style: TextStyle(fontSize: 16))),
                        if (q['status'] == 'answering') ...[
                          ElevatedButton(onPressed: () => _eval(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('+ CORRECT', style: TextStyle(fontSize: 16))),
                          ElevatedButton(onPressed: () => _eval(false), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('- WRONG', style: TextStyle(fontSize: 16))),
                        ],
                        ElevatedButton(onPressed: () => setState(() => _showAnswer = true), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('SHOW ANSWER', style: TextStyle(fontSize: 16))),
                        ElevatedButton(onPressed: _skip, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)), child: const Text('FINISH', style: TextStyle(fontSize: 16))),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ])),
    );
  }
}
