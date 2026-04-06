import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class DebugConsole extends StatefulWidget {
  const DebugConsole({
    super.key,
    this.onLogMessage,
    this.onTestSuccess,
  });

  final ValueChanged<String>? onLogMessage;
  final Future<void> Function()? onTestSuccess;

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  static const String _socketUrl = 'ws://127.0.0.1:8000/ws/logs';

  final List<String> _logs = <String>[];
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

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
        if (!mounted) {
          return;
        }
        setState(() {
          _logs.add(line);
        });
        _scrollToBottom();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() {
          _logs.add('[ERROR] WebSocket error: $error');
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _logs.add('[INFO] WebSocket disconnected.');
        });
        _scrollToBottom();
      },
      cancelOnError: false,
    );
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Text(
                    _logs[index],
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
