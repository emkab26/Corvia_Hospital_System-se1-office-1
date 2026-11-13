import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A utility class that defines breakpoints and provides helper methods
/// to build responsive UI layouts across mobile, tablet, and desktop viewports.
class ResponsiveLayout {
  // Screen size breakpoints
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 1200;

  /// Ceiling on how wide a column of content is allowed to get.
  ///
  /// A proportion of the viewport keeps growing with the display: at 70% an
  /// ultrawide monitor gives a 2400px line of text, which is past the point
  /// anyone can comfortably read. Independent of [tabletMaxWidth], which happens
  /// to share the value but answers a different question.
  static const double maxContentWidth = 1200;

  // Device type detection
  static bool isMobile(BuildContext context) {
    final mq = MediaQuery.of(context);
    // In landscape, use the shorter dimension to avoid treating a rotated
    // phone as a tablet just because its width is temporarily large.
    final shortSide = mq.size.shortestSide;
    return shortSide < mobileMaxWidth;
  }

  static bool isTablet(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortSide = mq.size.shortestSide;
    return shortSide >= mobileMaxWidth && shortSide < tabletMaxWidth;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletMaxWidth;

  static bool isWeb(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileMaxWidth;

  // Responsive sizing
  /// Width a main content column should be constrained to.
  ///
  /// Proportional to the viewport, then capped at [maxContentWidth]. The cap
  /// only bites above roughly 1715px, so narrower screens keep the width they
  /// had.
  static double getMainContentWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final double proportional;
    if (isDesktop(context)) {
      proportional = width * 0.7;
    } else if (isTablet(context)) {
      proportional = width * 0.8;
    } else {
      proportional = width;
    }
    return math.min(proportional, maxContentWidth);
  }

  static int getGridCrossAxisCount(BuildContext context) {
    if (isDesktop(context)) return 4;
    if (isTablet(context)) return 3;
    return 2;
  }

  static double getCardHeight(BuildContext context) {
    if (isDesktop(context)) return 180;
    if (isTablet(context)) return 160;
    return 140;
  }

  static double getButtonHeight(BuildContext context) {
    if (isDesktop(context)) return 55;
    if (isTablet(context)) return 50;
    return 45;
  }

  static double getIconSize(BuildContext context) {
    if (isDesktop(context)) return 32;
    if (isTablet(context)) return 28;
    return 24;
  }

  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(32);
    if (isTablet(context)) return const EdgeInsets.all(24);
    return const EdgeInsets.all(16);
  }

  static double getFontSize(BuildContext context,
      {required double mobile,
      required double tablet,
      required double desktop}) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  // Responsive layout builder
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }
}
