import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class DebugConsole extends StatefulWidget {
  const DebugConsole({super.key, this.onLogMessage, this.onTestSuccess});

  final ValueChanged<String>? onLogMessage;
  final Future<void> Function()? onTestSuccess;

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  static const String _socketUrl = 'ws://127.0.0.1:8000/ws/logs';
  static const int _maxLogEntries = 180;

  final List<_ConsoleLogEntry> _logs = <_ConsoleLogEntry>[];
  final Queue<_ConsoleLogEntry> _typingQueue = Queue<_ConsoleLogEntry>();
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    final channel = WebSocketChannel.connect(Uri.parse(_socketUrl));

    _channel = channel;
    _subscription = channel.stream.listen(
      (dynamic message) {
        final line = message.toString();
        widget.onLogMessage?.call(line);
        _appendLog(line);
      },
      onError: (Object error, StackTrace stackTrace) {
        _appendLog('[ERROR] WebSocket error: $error');
      },
      onDone: () {
        _appendLog('[INFO] WebSocket disconnected.');
      },
      cancelOnError: false,
    );
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }

    setState(() {
      final entry = _ConsoleLogEntry(fullText: line);
      _logs.add(entry);
      _typingQueue.add(entry);

      while (_logs.length > _maxLogEntries) {
        final removed = _logs.removeAt(0);
        _typingQueue.remove(removed);
      }
    });

    _startTypewriter();
    _scrollToBottom();
  }

  void _startTypewriter() {
    if (_typingTimer != null || _typingQueue.isEmpty) {
      return;
    }

    final entry = _typingQueue.first;
    _typingTimer = Timer.periodic(const Duration(milliseconds: 8), (timer) {
      if (!mounted) {
        timer.cancel();
        _typingTimer = null;
        return;
      }

      final visibleLength = entry.visibleText.length;
      if (visibleLength >= entry.fullText.length) {
        setState(() {
          entry.visibleText = entry.fullText;
          _typingQueue.remove(entry);
        });
        timer.cancel();
        _typingTimer = null;
        _scrollToBottom();
        _startTypewriter();
        return;
      }

      setState(() {
        entry.visibleText = entry.fullText.substring(0, visibleLength + 1);
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050607),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF123A1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1110),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'LIVE BACKEND LOGS',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: OutlinedButton(
                    onPressed: widget.onTestSuccess,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: Colors.greenAccent),
                      foregroundColor: Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 0,
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Test Success'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _logs.length,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: Text(
                    _logs[index].visibleText,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      color: Colors.greenAccent,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleLogEntry {
  _ConsoleLogEntry({required this.fullText});

  final String fullText;
  String visibleText = '';
}
