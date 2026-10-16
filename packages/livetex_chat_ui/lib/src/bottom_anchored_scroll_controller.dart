import "dart:math" as math;

import "package:flutter/widgets.dart";

class BottomAnchoredScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomAnchoredScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoredScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  @override
  bool applyViewportDimension(double viewportDimension) {
    if (hasViewportDimension && hasPixels && hasContentDimensions) {
      final delta = this.viewportDimension - viewportDimension;
      if (delta != 0) {
        final maxAfter = math.max(minScrollExtent, maxScrollExtent + delta);
        correctPixels(
          (pixels + delta).clamp(minScrollExtent, maxAfter).toDouble(),
        );
      }
    }
    return super.applyViewportDimension(viewportDimension);
  }
}
