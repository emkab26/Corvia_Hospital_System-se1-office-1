import 'package:flutter/material.dart';

/// NavigationBar clamps label text scaling to this, so measuring must too.
const double kNavigationBarMaxLabelTextScale = 1.3;

/// Largest font size, from [baseStyle]'s size down to [minFontSize], at which
/// every label in [labels] fits on one line within [slotWidth].
///
/// NavigationBar renders each label as a plain `Text` with no line limit, so a
/// label wider than its slot wraps instead of shrinking. Feeding this size into
/// the bar's `labelTextStyle` keeps every label on one line.
double fitNavigationLabelFontSize({
  required List<String> labels,
  required TextStyle baseStyle,
  required double slotWidth,
  required TextScaler textScaler,
  double minFontSize = 9,
}) {
  bool fits(double fontSize) {
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
            text: label, style: baseStyle.copyWith(fontSize: fontSize)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width > slotWidth) {
        return false;
      }
    }
    return true;
  }

  for (var size = baseStyle.fontSize ?? 12; size > minFontSize; size -= 0.5) {
    if (fits(size)) {
      return size;
    }
  }
  return minFontSize;
}
