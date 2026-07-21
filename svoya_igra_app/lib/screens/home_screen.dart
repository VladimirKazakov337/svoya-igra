import 'package:flutter/material.dart';
import 'template_editor.dart';
import 'player_screen.dart';
import '../services/api_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Svoya Igra', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplateEditor())),
              child: const Text('Create Game'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
              child: const Text('Join Game'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DraftsScreen())),
              child: const Text('My Drafts'),
            ),
          ],
        ),
      ),
    );
  }
}

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});
  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<Map<String, dynamic>> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drafts = await ApiService.loadDrafts();
    setState(() { _drafts = drafts; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Drafts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _drafts.isEmpty
              ? const Center(child: Text('No drafts'))
              : ListView.builder(
                  itemCount: _drafts.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(_drafts[i]['name'] ?? 'Draft'),
                    onTap: () async {
                      final template = await ApiService.loadDraft(_drafts[i]['id']);
                      if (template != null && mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TemplateEditor(loadedTemplate: template)));
                      }
                    },
                  ),
                ),
    );
  }
}
