import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
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
  String? _pendingQKey;
  String? _pendingAKey;

  @override
  void initState() {
    super.initState();
    _gameNameCtrl = TextEditingController(text: widget.loadedTemplate?['name'] ?? 'My Game');
    _hostNameCtrl = TextEditingController(text: 'Host');
    if (widget.loadedTemplate != null) {
      _rounds = List<Map<String, dynamic>>.from(widget.loadedTemplate!['rounds'] ?? []);
      _finalThemes = List<Map<String, dynamic>>.from(widget.loadedTemplate!['final'] ?? []);
    } else { _initTemplate(); }
    _setupGlobalListeners();
  }

  void _initTemplate() {
    _rounds = [];
    for (final prices in [_prices1, _prices2, _prices3]) {
      final categories = <Map<String, dynamic>>[];
      for (int c = 0; c < 5; c++) {
        final questions = <Map<String, dynamic>>[];
        for (final price in prices) { questions.add({'price': price, 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''}); }
        categories.add({'name': 'Theme ${c + 1}', 'questions': questions});
      }
      _rounds.add({'name': 'Round ${_rounds.length + 1}', 'categories': categories});
    }
    _finalThemes = List.generate(10, (i) => {'name': 'Theme ${i + 1}', 'text': '', 'answer': '', 'qmedia': '', 'amedia': ''});
  }

  void _setupGlobalListeners() {
    html.document.onDragOver.listen((e) => e.preventDefault());
    html.document.onDrop.listen((e) {
      e.preventDefault();
      final dt = (e as dynamic).dataTransfer as html.DataTransfer?;
      if (dt?.files?.isNotEmpty == true) _handleFile(dt!.files![0]);
    });
    html.document.body?.onPaste.listen((e) {
      final cd = (e as dynamic).clipboardData as html.DataTransfer?;
      if (cd?.files?.isNotEmpty == true) { e.preventDefault(); _handleFile(cd!.files![0]); }
    });
    // Also listen on window for paste events
    html.window.addEventListener('paste', (html.Event e) {
      final cd = (e as dynamic).clipboardData as html.DataTransfer?;
      if (cd?.files?.isNotEmpty == true) {
        e.preventDefault();
        _handleFile(cd!.files![0]);
      }
    });
  }

  void _handleFile(html.File file) {
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      Uint8List? bytes;
      if (result is Uint8List) { bytes = result; }
      else if (result is List<int>) { bytes = Uint8List.fromList(result); }
      if (bytes != null) _uploadAndSet(bytes, file.name);
    });
    reader.readAsArrayBuffer(file);
  }

  Future<void> _uploadAndSet(Uint8List bytes, String filename) async {
    final url = await _uploadBytes(bytes, filename);
    if (url == null) return;
    setState(() {
      if (_pendingQKey != null) { _setMediaByKey(_pendingQKey!, url); _pendingQKey = null; }
      if (_pendingAKey != null) { _setMediaByKey(_pendingAKey!, url); _pendingAKey = null; }
    });
  }

  void _setMediaByKey(String key, String url) {
    final parts = key.split('_');
    final type = parts[0]; final r = int.parse(parts[1]); final c = int.parse(parts[2]); final q = int.parse(parts[3]);
    if (type == 'q') { _rounds[r]['categories'][c]['questions'][q]['qmedia'] = url; }
    else { _rounds[r]['categories'][c]['questions'][q]['amedia'] = url; }
  }

  Future<String?> _uploadBytes(Uint8List bytes, String filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('http://localhost:8000/api/upload'));
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final response = await request.send();
      if (response.statusCode == 200) { return jsonDecode(await response.stream.bytesToString())['url']; }
    } catch (e) { print('Upload error: $e'); }
    return null;
  }

  void _pickFile(String key) {
    final input = html.FileUploadInputElement()..accept = 'image/*,audio/*'..multiple = false;
    input.click();
    input.onChange.listen((_) {
      final file = input.files?.first;
      if (file != null) {
        if (key.startsWith('q')) { _pendingQKey = key; } else { _pendingAKey = key; }
        _handleFile(file);
      }
    });
  }

  @override
  void dispose() { _gameNameCtrl.dispose(); _hostNameCtrl.dispose(); super.dispose(); }

  Future<void> _saveDraft() async {
    final template = {'name': _gameNameCtrl.text, 'rounds': _rounds, 'final': _finalThemes};
    final draftId = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
    await http.post(Uri.parse('http://localhost:8000/api/draft/save'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'id': draftId, 'template': template}));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft saved!')));
  }

  Future<void> _startGame() async {
    final template = {'name': _gameNameCtrl.text, 'rounds': _rounds, 'final': _finalThemes};
    final resp = await http.post(Uri.parse('http://localhost:8000/api/create_room'));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final roomCode = data['room_code'];
      await http.post(Uri.parse('http://localhost:8000/api/save_template/$roomCode'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(template));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LobbyScreen(roomCode: roomCode, hostName: _hostNameCtrl.text, template: template)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Game')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Expanded(child: TextField(controller: _gameNameCtrl, decoration: const InputDecoration(labelText: 'Game name'))),
          const SizedBox(width: 10), Expanded(child: TextField(controller: _hostNameCtrl, decoration: const InputDecoration(labelText: 'Host name'))),
        ])),
        Row(children: [_buildTab('Round 1', 0), _buildTab('Round 2', 1), _buildTab('Round 3', 2), _buildTab('Final', 3)]),
        Expanded(child: _currentRound < 3 ? _buildRoundEditor() : _buildFinalEditor()),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(onPressed: _saveDraft, child: const Text('Save Draft')),
          const SizedBox(width: 10), ElevatedButton(onPressed: _startGame, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Start Game')),
        ]),
        const SizedBox(height: 10),
      ]),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _currentRound == index;
    return Expanded(child: GestureDetector(onTap: () => setState(() => _currentRound = index),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12), color: isActive ? Colors.orange : Colors.blue[800],
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black : Colors.white))),
    ));
  }

  Widget _buildRoundEditor() {
    final round = _rounds[_currentRound];
    final categories = round['categories'] as List<dynamic>;
    return ListView.builder(itemCount: categories.length, itemBuilder: (context, catIdx) {
      final cat = categories[catIdx] as Map<String, dynamic>;
      final questions = cat['questions'] as List<dynamic>;
      return Card(color: const Color(0xFF2A2A4A), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        TextField(controller: TextEditingController(text: cat['name']), decoration: const InputDecoration(labelText: 'Theme name'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), onChanged: (v) => cat['name'] = v),
        ...questions.asMap().entries.map((entry) {
          final qIdx = entry.key;
          final q = entry.value as Map<String, dynamic>;
          final qKey = 'q_${_currentRound}_${catIdx}_$qIdx';
          final aKey = 'a_${_currentRound}_${catIdx}_$qIdx';
          return Container(
            margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF111133), borderRadius: BorderRadius.circular(8),
                border: const Border(left: BorderSide(color: Colors.orange, width: 4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q['price']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 5),
              TextField(controller: TextEditingController(text: q['text']), decoration: const InputDecoration(labelText: 'Question'), maxLines: 2, onChanged: (v) => q['text'] = v),
              const SizedBox(height: 8),
              // Media for Question
              _buildMediaRow('Question media', q['qmedia'], () { _pendingQKey = qKey; _pickFile(qKey); }, () => setState(() => q['qmedia'] = '')),
              const SizedBox(height: 8),
              TextField(controller: TextEditingController(text: q['answer']), decoration: const InputDecoration(labelText: 'Answer'), onChanged: (v) => q['answer'] = v),
              const SizedBox(height: 8),
              // Media for Answer
              _buildMediaRow('Answer media', q['amedia'], () { _pendingAKey = aKey; _pickFile(aKey); }, () => setState(() => q['amedia'] = '')),
            ]),
          );
        }),
      ])));
    });
  }

  Widget _buildMediaRow(String label, String? url, VoidCallback onPick, VoidCallback onClear) {
    final hasFile = url != null && url.isNotEmpty;
    final isImage = hasFile && url.contains('/uploads/');
    final displayUrl = hasFile ? 'http://localhost:8000$url' : '';

    return Row(children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onPick,
        child: Container(
          width: 80, height: 60,
          decoration: BoxDecoration(border: Border.all(color: hasFile ? Colors.green : Colors.grey, width: 2), borderRadius: BorderRadius.circular(6)),
          child: hasFile
              ? Stack(children: [
                  Center(child: isImage
                      ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(displayUrl, width: 70, height: 50, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 30, color: Colors.green)))
                      : const Icon(Icons.audiotrack, size: 30, color: Colors.green)),
                  Positioned(top: 1, right: 1, child: GestureDetector(onTap: onClear, child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
                ])
              : const Icon(Icons.add_photo_alternate, size: 24, color: Colors.grey),
        ),
      ),
      const SizedBox(width: 8),
      if (!hasFile) const Text('Click or Ctrl+V', style: TextStyle(fontSize: 9, color: Colors.grey)),
    ]);
  }

  Widget _buildFinalEditor() {
    return ListView.builder(itemCount: _finalThemes.length, itemBuilder: (context, idx) {
      final theme = _finalThemes[idx];
      return Card(color: const Color(0xFF2A2A4A), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text('${theme['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        TextField(controller: TextEditingController(text: theme['text']), decoration: const InputDecoration(labelText: 'Question'), onChanged: (v) => theme['text'] = v),
        TextField(controller: TextEditingController(text: theme['answer']), decoration: const InputDecoration(labelText: 'Answer'), onChanged: (v) => theme['answer'] = v),
      ])));
    });
  }
}
