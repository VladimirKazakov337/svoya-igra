import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

void main() => runApp(const SvoyaIgraApp());

class SvoyaIgraApp extends StatelessWidget {
  const SvoyaIgraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Svoya Igra',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}

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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HostScreen()),
              ),
              child: const Text('Create Game'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: const Text('Join Game'),
            ),
          ],
        ),
      ),
    );
  }
}

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});
  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host')),
      body: const Center(child: Text('Host interface - coming soon')),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _roomController = TextEditingController();
  final _nameController = TextEditingController();
  WebSocketChannel? _channel;

  void _connect() {
    final room = _roomController.text.trim().toUpperCase();
    final name = _nameController.text.trim();
    if (room.isEmpty || name.isEmpty) return;
    final playerId = DateTime.now().millisecondsSinceEpoch.toString();
    final uri = Uri.parse('ws://localhost:8000/ws/$room/$playerId');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((data) {
      final msg = jsonDecode(data);
      print('Received: ${msg['type']}');
    });
    _channel!.sink.add(jsonEncode({'type': 'join', 'name': name}));
    setState(() {});
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _roomController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Game')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _roomController,
              decoration: const InputDecoration(labelText: 'Room code'),
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _connect, child: const Text('Join')),
          ],
        ),
      ),
    );
  }
}