import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Corvia mark, drawn from the vector asset so it stays sharp at any
/// size. Pass [badge] to place it on a white circle, which keeps the teal-to-
/// navy gradient readable on coloured or dark backgrounds.
class CorviaLogo extends StatelessWidget {
  const CorviaLogo({
    super.key,
    this.size = 40,
    this.badge = false,
  });

  static const String assetPath = 'assets/icon/corvia_mark.svg';

  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      assetPath,
      width: badge ? size * 0.78 : size,
      height: badge ? size * 0.78 : size,
      semanticsLabel: 'Corvia logo',
    );

    if (!badge) return mark;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: mark,
    );
  }
}
