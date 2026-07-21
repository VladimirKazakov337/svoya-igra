import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'lobby_screen.dart';

class TemplateEditor extends StatefulWidget {
  final Map<String, dynamic>? loadedTemplate;
  const TemplateEditor({super.key, this.loadedTemplate});
  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late TextEditingController _gameNameCtrl;
  late TextEditingController _hostNameCtrl;
  int _currentRound = 0;

  final List<int> _prices1 = [100, 200, 300, 400, 500];
  final List<int> _prices2 = [200, 400, 600, 800, 1000];
  final List<int> _prices3 = [300, 600, 900, 1200, 1500];

  late List<Map<String, dynamic>> _rounds;
  late List<Map<String, dynamic>> _finalThemes;

  @override
  void initState() {
    super.initState();
    _gameNameCtrl = TextEditingController(text: widget.loadedTemplate?['name'] ?? 'My Game');
    _hostNameCtrl = TextEditingController(text: 'Host');
    if (widget.loadedTemplate != null) {
      _rounds = List<Map<String, dynamic>>.from(widget.loadedTemplate!['rounds'] ?? []);
      _finalThemes = List<Map<String, dynamic>>.from(widget.loadedTemplate!['final'] ?? []);
    } else {
      _initTemplate();
    }
  }

  void _initTemplate() {
    _rounds = [];
    for (final prices in [_prices1, _prices2, _prices3]) {
      final categories = <Map<String, dynamic>>[];
      for (int c = 0; c < 5; c++) {
        final questions = <Map<String, dynamic>>[];
        for (final price in prices) {
          questions.add({'price': price, 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''});
        }
        categories.add({'name': 'Theme ${c + 1}', 'questions': questions});
      }
      _rounds.add({'name': 'Round ${_rounds.length + 1}', 'categories': categories});
    }
    _finalThemes = List.generate(10, (i) => {'name': 'Theme ${i + 1}', 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''});
  }

  @override
  void dispose() {
    _gameNameCtrl.dispose();
    _hostNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    final template = {'name': _gameNameCtrl.text, 'rounds': _rounds, 'final': _finalThemes};
    final draftId = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
    await http.post(
      Uri.parse('http://localhost:8000/api/draft/save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': draftId, 'template': template}),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft saved!')));
  }

  Future<void> _startGame() async {
    final template = {'name': _gameNameCtrl.text, 'rounds': _rounds, 'final': _finalThemes};
    final resp = await http.post(Uri.parse('http://localhost:8000/api/create_room'));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final roomCode = data['room_code'];
      await http.post(
        Uri.parse('http://localhost:8000/api/save_template/$roomCode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(template),
      );
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => LobbyScreen(roomCode: roomCode, hostName: _hostNameCtrl.text, template: template),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Game')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _gameNameCtrl, decoration: const InputDecoration(labelText: 'Game name'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _hostNameCtrl, decoration: const InputDecoration(labelText: 'Host name'))),
              ],
            ),
          ),
          Row(children: [_buildTab('Round 1', 0), _buildTab('Round 2', 1), _buildTab('Round 3', 2), _buildTab('Final', 3)]),
          Expanded(child: _currentRound < 3 ? _buildRoundEditor() : _buildFinalEditor()),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(onPressed: _saveDraft, child: const Text('Save Draft')),
            const SizedBox(width: 10),
            ElevatedButton(onPressed: _startGame, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Start Game')),
          ]),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _currentRound == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentRound = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: isActive ? Colors.orange : Colors.blue[800],
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black : Colors.white)),
        ),
      ),
    );
  }

  Widget _buildRoundEditor() {
    final round = _rounds[_currentRound];
    final categories = round['categories'] as List<dynamic>;
    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, catIdx) {
        final cat = categories[catIdx] as Map<String, dynamic>;
        final questions = cat['questions'] as List<dynamic>;
        return Card(
          color: const Color(0xFF2A2A4A),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: TextEditingController(text: cat['name']),
                decoration: const InputDecoration(labelText: 'Theme name'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                onChanged: (v) => cat['name'] = v,
              ),
              ...questions.asMap().entries.map((entry) {
                final q = entry.value as Map<String, dynamic>;
                final qMediaCtrl = TextEditingController(text: q['qmedia'] ?? '');
                final aMediaCtrl = TextEditingController(text: q['amedia'] ?? '');
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF111133), borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: Colors.orange, width: 4))),
                  child: Column(children: [
                    Text('${q['price']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
                    TextField(controller: TextEditingController(text: q['text']), decoration: const InputDecoration(labelText: 'Question'), onChanged: (v) => q['text'] = v),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(child: TextField(controller: TextEditingController(text: q['answer']), decoration: const InputDecoration(labelText: 'Answer'), onChanged: (v) => q['answer'] = v)),
                      const SizedBox(width: 10),
                      // URL input for Q media
                      SizedBox(width: 120, child: TextField(controller: qMediaCtrl, decoration: const InputDecoration(hintText: 'URL or paste', isDense: true), onChanged: (v) => q['qmedia'] = v)),
                      if (q['qmedia'] != null && q['qmedia'] != '')
                        Image.network(q['qmedia'], width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 30)),
                      const SizedBox(width: 5),
                      SizedBox(width: 120, child: TextField(controller: aMediaCtrl, decoration: const InputDecoration(hintText: 'URL or paste', isDense: true), onChanged: (v) => q['amedia'] = v)),
                      if (q['amedia'] != null && q['amedia'] != '')
                        Image.network(q['amedia'], width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 30)),
                    ]),
                  ]),
                );
              }),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildFinalEditor() {
    return ListView.builder(
      itemCount: _finalThemes.length,
      itemBuilder: (context, idx) {
        final theme = _finalThemes[idx];
        return Card(
          color: const Color(0xFF2A2A4A),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('${theme['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextField(controller: TextEditingController(text: theme['text']), decoration: const InputDecoration(labelText: 'Question'), onChanged: (v) => theme['text'] = v),
              TextField(controller: TextEditingController(text: theme['answer']), decoration: const InputDecoration(labelText: 'Answer'), onChanged: (v) => theme['answer'] = v),
            ]),
          ),
        );
      },
    );
  }
}
