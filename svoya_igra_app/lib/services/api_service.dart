import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8000';

  static Future<String?> createRoom(Map<String, dynamic> template) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/create_room'));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final roomCode = data['room_code'];
      await http.post(
        Uri.parse('$baseUrl/api/save_template/$roomCode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(template),
      );
      return roomCode;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> loadDrafts() async {
    final resp = await http.get(Uri.parse('$baseUrl/api/drafts'));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return List<Map<String, dynamic>>.from(data['drafts'] ?? []);
    }
    return [];
  }

  static Future<Map<String, dynamic>?> loadDraft(String id) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/draft/load'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': id}),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data['status'] == 'ok') return data['template'];
    }
    return null;
  }

  static Future<void> saveDraft(Map<String, dynamic> template) async {
    final draftId = DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
    await http.post(
      Uri.parse('$baseUrl/api/draft/save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': draftId, 'template': template}),
    );
  }
}
