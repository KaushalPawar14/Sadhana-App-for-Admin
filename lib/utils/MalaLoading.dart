import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class CustomLoader extends StatefulWidget {
  final double size;

  const CustomLoader({super.key, this.size = 100});

  @override
  State<CustomLoader> createState() => _CustomLoaderState();
}

class _CustomLoaderState extends State<CustomLoader>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/emoji/mala.json',
        width: widget.size,
        height: widget.size,

        controller: _controller,

        onLoaded: (composition) {
          // 🚀 Make animation faster (adjust here)
          _controller.duration = composition.duration ~/ 1; // 3x faster

          _controller.repeat();
        },

        fit: BoxFit.contain,
      ),
    );
  }
}