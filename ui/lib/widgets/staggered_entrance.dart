import 'dart:async';

import 'package:flutter/material.dart';

/// Fades and slides a list item in, staggered by its index.
///
/// Bumping [replayToken] replays the animation for the whole list, which is how
/// the completed-tasks view and the vault dialog re-animate when reopened.
class StaggeredEntranceItem extends StatefulWidget {
  const StaggeredEntranceItem({
    super.key,
    required this.index,
    required this.replayToken,
    required this.child,
  });

  final int index;
  final int replayToken;
  final Widget child;

  @override
  State<StaggeredEntranceItem> createState() => _StaggeredEntranceItemState();
}

class _StaggeredEntranceItemState extends State<StaggeredEntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _delayTimer;
  int _scheduleToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scheduleAnimation();
  }

  @override
  void didUpdateWidget(covariant StaggeredEntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replayToken != widget.replayToken ||
        oldWidget.index != widget.index) {
      _scheduleAnimation();
    }
  }

  void _scheduleAnimation() {
    _delayTimer?.cancel();
    _controller.value = 0;
    final token = ++_scheduleToken;
    _delayTimer = Timer(Duration(milliseconds: widget.index * 50), () {
      if (!mounted || token != _scheduleToken) {
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
