import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

class AvatarShimmer extends StatelessWidget {
  final double radius;

  const AvatarShimmer({
    super.key,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.cBgSecondary,
      highlightColor: context.cDivider,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
      ),
    );
  }
}
