import 'dart:async';
import 'package:flutter/material.dart';

/// A text widget that automatically scrolls horizontally when the text overflows.
/// Scrolls back and forth with a pause at each end, with subtle fade edges.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double scrollSpeed;
  final Duration pauseDuration;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrollSpeed = 30.0,
    this.pauseDuration = const Duration(seconds: 2),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController;
  Timer? _timer;
  bool _overflows = false;
  bool _forward = true;
  static const _edgeFadeWidth = 20.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stopScrolling();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _forward = true;
      _overflows = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _checkOverflow() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final nowOverflows = maxScroll > 0;
    if (nowOverflows != _overflows) {
      setState(() => _overflows = nowOverflows);
    }
    if (nowOverflows) {
      _startScrolling();
    } else {
      _stopScrolling();
    }
  }

  void _startScrolling() {
    _timer?.cancel();
    _timer = Timer(widget.pauseDuration, _animateScroll);
  }

  void _animateScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final target = _forward ? maxScroll : 0.0;
    final current = _scrollController.offset;
    final distance = (target - current).abs();
    if (distance < 1.0) {
      _forward = !_forward;
      _timer?.cancel();
      _timer = Timer(widget.pauseDuration, _animateScroll);
      return;
    }
    final duration = Duration(
      milliseconds: (distance / widget.scrollSpeed * 1000).toInt().clamp(100, 30000),
    );

    _scrollController
        .animateTo(target, duration: duration, curve: Curves.linear)
        .then((_) {
      if (!mounted) return;
      _forward = !_forward;
      _timer?.cancel();
      _timer = Timer(widget.pauseDuration, _animateScroll);
    });
  }

  void _stopScrolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopScrolling();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );

    if (!_overflows) return child;

    return ShaderMask(
      shaderCallback: (rect) {
        return LinearGradient(
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [
            0.0,
            (_edgeFadeWidth / rect.width).clamp(0.0, 0.3),
            (1.0 - _edgeFadeWidth / rect.width).clamp(0.7, 1.0),
            1.0,
          ],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
