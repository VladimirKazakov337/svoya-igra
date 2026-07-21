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
  List<Map<String, dynamic>> _finalThemes = [];
  Map<String, dynamic>? _finalTheme;
  String _finalPhase = '';
  Map<String, bool> _finalCorrect = {};
  bool _showFinalAnswerTable = false;

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
      if (msg['type'] == 'final_update') {
        if (msg['final_bets'] != null) _game['final_bets'] = msg['final_bets'];
        if (msg['final_answers'] != null) _game['final_answers'] = msg['final_answers'];
        setState(() {});
      }
      if (msg['type'] == 'final_scores') _showFinalResults(msg['scores']);
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
      _finalPhase = _game['final_phase'] ?? '';
      // Init final themes
      if (_game['phase'] == 'final' && _finalThemes.isEmpty) {
        final themes = _game['final'] as List? ?? [];
        _finalThemes = themes.asMap().entries.map((e) {
          final t = e.value as Map<String, dynamic>? ?? {};
          return {...t, 'index': e.key, 'eliminated': false};
        }).toList();
      }
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
  void _skip() => _send('skip_question');
  void _next() => _send('next_round');
  void _skipToFinal() => _send('skip_to_final');

  void _eliminateTheme(int idx) {
    setState(() => _finalThemes[idx]['eliminated'] = true);
  }

  void _showFinalQuestion(int idx) {
    _finalTheme = _finalThemes[idx];
    setState(() {});
  }

  void _allowBets() { _send('show_final_question', {'action': 'betting'}); setState(() => _finalPhase = 'betting'); }
  void _goToAnswering() { _send('show_final_question', {'action': 'answering'}); setState(() => _finalPhase = 'answering'); }
  void _applyFinalResults() {
    _send('final_results', {'results': _finalCorrect});
  }

  void _showFinalResults(Map scores) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('RESULTS', textAlign: TextAlign.center, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ...(scores.values).map((s) {
                final name = s['name'] ?? '';
                final score = s['score'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('$name: $score', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _ws?.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isFinal = _game['phase'] == 'final';
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
              Text(isFinal ? 'FINAL ROUND' : '${round['name'] ?? 'Round'} (${_currentRound + 1}/3)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          Expanded(child: isFinal ? _buildFinalBoard() : _buildRoundBoard(cats, prices, questions, q)),
          if (!isFinal) Container(padding: const EdgeInsets.all(6), color: const Color(0xFF1A1A3E), height: 45,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_game['answering_name'] != null && _game['answering_name'] != '')
                Text('ANSWERING: ${_game['answering_name']}', style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton(onPressed: _skipToFinal, child: const Text('Skip to Final', style: TextStyle(fontSize: 11))),
              if (q == null && questions.isEmpty) ElevatedButton(onPressed: _next, child: const Text('Next Round', style: TextStyle(fontSize: 11))),
            ]),
          ),
        ]),
        // Overlay for regular questions
        if (!isFinal && q != null) _buildQuestionOverlay(q),
        // Overlay for final question
        if (isFinal && _finalTheme != null) _buildFinalOverlay(),
      ])),
    );
  }

  Widget _buildRoundBoard(List cats, List prices, Map questions, Map? q) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(3),
      child: Column(children: [
        Row(children: cats.map((c) => Expanded(child: Container(
          height: 32, alignment: Alignment.center, color: Colors.orange, margin: const EdgeInsets.all(1),
          child: Text(c.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
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
            onPressed: (exists && q == null) ? () => _select(cat.toString(), price) : null,
            child: exists ? Text('$price', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)) : null,
          )));
        }).toList())),
      ]),
    );
  }

  Widget _buildFinalBoard() {
    final active = _finalThemes.where((t) => t['eliminated'] != true).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: _finalThemes.map((t) {
        if (t['eliminated'] == true) return const SizedBox(width: 150, height: 80);
        final isLast = active.length == 1;
        return SizedBox(
          width: 150, height: 80,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isLast ? Colors.green : Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => isLast ? _showFinalQuestion(t['index']) : _eliminateTheme(t['index']),
            child: Text(t['name'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        );
      }).toList()),
    );
  }

  Widget _buildQuestionOverlay(Map q) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        color: Colors.black.withOpacity(0.95),
        child: Center(child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(25), padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(q['question']?['text'] ?? '', style: const TextStyle(fontSize: 24, color: Colors.white)),
              const SizedBox(height: 15),
              if (q['question']?['qmedia'] != null && q['question']?['qmedia'] != '')
                Image.network(q['question']['qmedia'], height: 200, fit: BoxFit.contain),
              if (_showAnswer && q['question']?['answer'] != null)
                Padding(padding: const EdgeInsets.all(12), child: Text('ANSWER: ${q['question']['answer']}', style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold))),
              if (_game['answering_name'] != null && _game['answering_name'] != '')
                Text('ANSWERING: ${_game['answering_name']}', style: const TextStyle(color: Colors.orange, fontSize: 20)),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                if (q['status'] == 'selected' || q['status'] == 'open')
                  ElevatedButton(onPressed: _activate, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('ACTIVATE ANSWER')),
                if (q['status'] == 'answering') ...[
                  ElevatedButton(onPressed: () => _eval(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('+ CORRECT')),
                  ElevatedButton(onPressed: () => _eval(false), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('- WRONG')),
                ],
                ElevatedButton(onPressed: () => setState(() => _showAnswer = true), child: const Text('SHOW ANSWER')),
                ElevatedButton(onPressed: _skip, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text('FINISH')),
              ]),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _buildFinalOverlay() {
    final t = _finalTheme!;
    return Container(
      color: Colors.black.withOpacity(0.95),
      child: Center(child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(25), padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t['name'] ?? '', style: const TextStyle(fontSize: 24, color: Colors.orange, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            if (_finalPhase.isEmpty)
              ElevatedButton(onPressed: _allowBets, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15)), child: const Text('ALLOW BETS'))
            else if (_finalPhase == 'betting')
              Wrap(spacing: 10, children: [
                ElevatedButton(onPressed: _allowBets, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('ALLOW BETS')),
                ElevatedButton(onPressed: _goToAnswering, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('SHOW QUESTION')),
              ])
            else if (_finalPhase == 'answering') ...[
              Text(t['text'] ?? '', style: const TextStyle(fontSize: 22, color: Colors.white)),
              if (t['qmedia'] != null && t['qmedia'] != '')
                Image.network(t['qmedia'], height: 180),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () => _showFinalAnswer(), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('SHOW ANSWER')),
            ],
            const SizedBox(height: 15),
            // Final status
            if (_game['final_bets'] != null)
              ...(_game['final_bets'] as Map).entries.map((e) => Text('${e.key}: bet ${e.value}', style: const TextStyle(fontSize: 14, color: Colors.green))),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: () { _finalTheme = null; setState(() {}); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text('CLOSE')),
          ]),
        ),
      )),
    );
  }

  void _showFinalAnswer() {
    final t = _finalTheme!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ANSWER: ${t['answer'] ?? ''}', style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          // Table with players, bets, answers
          ..._players.map((p) {
            final id = _players.indexOf(p).toString();
            final bet = (_game['final_bets'] as Map?)?.entries.firstWhere((e) => e.key == id, orElse: () => MapEntry('', 0)).value ?? 0;
            return Text('${p['name']}: bet $bet', style: const TextStyle(fontSize: 16));
          }),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _applyFinalResults, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('APPLY RESULTS')),
        ]),
      ),
    );
  }
}
