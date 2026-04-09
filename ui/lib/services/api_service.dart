import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TaskSummary {
  TaskSummary({
    required this.id,
    required this.title,
    required this.className,
    required this.dueDate,
    required this.description,
  });

  final String id;
  final String title;
  final String className;
  final String? dueDate;
  final String description;

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    return TaskSummary(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled Task').toString(),
      className: (json['class_name'] ?? 'Unknown Class').toString(),
      dueDate: json['due_date']?.toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String _baseUrl = 'http://127.0.0.1:8000';

  final http.Client _client;

  List<TaskSummary> _decodeTasksFromPayload(dynamic payload) {
    final tasks = payload is Map<String, dynamic>
        ? payload['tasks'] as List<dynamic>? ?? <dynamic>[]
        : <dynamic>[];

    return tasks
        .whereType<Map<String, dynamic>>()
        .map(TaskSummary.fromJson)
        .toList();
  }

  Future<List<TaskSummary>> getTasks() async {
    final uri = Uri.parse('$_baseUrl/tasks');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tasks: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    return _decodeTasksFromPayload(payload);
  }

  Future<List<TaskSummary>> getHiddenTasks() async {
    final uri = Uri.parse('$_baseUrl/tasks/hidden');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch hidden tasks: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    return _decodeTasksFromPayload(payload);
  }

  Future<void> hideTask(TaskSummary task) async {
    final uri = Uri.parse('$_baseUrl/tasks/hide');
    final response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{
        'task_id': task.id,
        'task_title': task.title,
        'class_name': task.className,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to hide task: ${response.statusCode}');
    }
  }

  Future<void> recoverTask(String taskId) async {
    final uri = Uri.parse('$_baseUrl/tasks/recover');
    final response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{'task_id': taskId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to recover task: ${response.statusCode}');
    }
  }

  Future<void> permanentlyDeleteTask(String taskId) async {
    final uri = Uri.parse('$_baseUrl/tasks/permanent');
    final request = http.Request('DELETE', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(<String, String>{'task_id': taskId});

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Failed to permanently delete task: ${response.statusCode}');
    }
  }

  Future<String> getDraft(String className, String taskTitle) async {
    final uri = Uri.parse(
      '$_baseUrl/tasks/${Uri.encodeComponent(className)}/${Uri.encodeComponent(taskTitle)}/draft',
    );
    final response = await _client.get(uri);

    if (response.statusCode == 404) {
      throw Exception('Draft not found yet.');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch draft: ${response.statusCode}');
    }

    return response.body;
  }

  Future<void> triggerScrape() async {
    final uri = Uri.parse('$_baseUrl/scrape');
    final response = await _client.post(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to trigger scrape: ${response.statusCode}');
    }
  }

  Future<void> triggerGenerate(
    String mode, {
    String? className,
    String? taskTitle,
    String? customInstructions,
    File? attachmentFile,
  }) async {
    final uri = Uri.parse('$_baseUrl/generate');
    final request = http.MultipartRequest('POST', uri)
      ..fields['mode'] = mode
      ..fields['custom_instructions'] = customInstructions ?? '';

    if (className != null) {
      request.fields['class_name'] = className;
    }
    if (taskTitle != null) {
      request.fields['task_title'] = taskTitle;
    }
    if (attachmentFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('attachment', attachmentFile.path),
      );
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Failed to trigger generation: ${response.statusCode}');
    }
  }

  Future<List<VaultDraft>> getVaultDrafts() async {
    final uri = Uri.parse('$_baseUrl/vault');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch vault: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    final drafts = payload is Map<String, dynamic>
        ? payload['drafts'] as List<dynamic>? ?? <dynamic>[]
        : <dynamic>[];

    return drafts
        .whereType<Map<String, dynamic>>()
        .map(VaultDraft.fromJson)
        .toList();
  }
}

class VaultDraft {
  VaultDraft({
    required this.id,
    required this.taskTitle,
    required this.className,
    required this.mode,
    required this.createdAt,
    required this.content,
  });

  final int id;
  final String taskTitle;
  final String className;
  final String mode;
  final String createdAt;
  final String content;

  factory VaultDraft.fromJson(Map<String, dynamic> json) {
    return VaultDraft(
      id: (json['id'] as num?)?.toInt() ?? 0,
      taskTitle: (json['task_title'] ?? 'Untitled Task').toString(),
      className: (json['class_name'] ?? 'Unknown Class').toString(),
      mode: (json['mode'] ?? 'tutor').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
    );
  }
}
