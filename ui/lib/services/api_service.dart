import 'dart:convert';

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

  Future<List<TaskSummary>> getTasks() async {
    final uri = Uri.parse('$_baseUrl/tasks');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tasks: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body);
    final tasks = payload is Map<String, dynamic>
        ? payload['tasks'] as List<dynamic>? ?? <dynamic>[]
        : <dynamic>[];

    return tasks
        .whereType<Map<String, dynamic>>()
        .map(TaskSummary.fromJson)
        .toList();
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
  }) async {
    final queryParams = <String, String>{
      'mode': mode,
    };
    if (className != null && taskTitle != null) {
      queryParams['class_name'] = className;
      queryParams['task_title'] = taskTitle;
    }

    final uri = Uri.parse('$_baseUrl/generate').replace(queryParameters: queryParams);
    final response = await _client.post(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to trigger generation: ${response.statusCode}');
    }
  }
}
