import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A DRAG HANDLE FOR EVERY KIND OF POINTER. The board's cards are picked up in the way each device expects:
///
///   TOUCH (a phone, a tablet)     press and hold, then drag (the long press, unchanged: a plain swipe still scrolls the board)
///   MOUSE and TRACKPAD (a laptop) click and drag at once, no waiting; the pointer shows an open hand over a card
///
/// Why two: the long press alone does not work with a mouse. The app lets a mouse drag scroll the board, so a click-and-drag moved the lists and
/// the card was never picked up unless the button was held still for half a second first. Both draggables carry the same data and the same callbacks,
/// and each ignores the other's pointers, so a drag is always started by exactly one of them.
class BoardDraggable<T extends Object> extends StatelessWidget {
  const BoardDraggable({
    super.key,
    required this.data,
    required this.feedback,
    required this.child,
    this.childWhenDragging,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDraggableCanceled,
    this.onDragCompleted,
  });

  final T data;
  final Widget feedback;
  final Widget child;
  final Widget? childWhenDragging;
  final VoidCallback? onDragStarted;
  final DragUpdateCallback? onDragUpdate;
  final DragEndCallback? onDragEnd;
  final DraggableCanceledCallback? onDraggableCanceled;
  final VoidCallback? onDragCompleted;

  /// The pointers that drag at once (the others press and hold).
  static bool picksUpAtOnce(PointerDeviceKind kind) => kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  @override
  Widget build(BuildContext context) {
    final touch = _TouchDraggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDraggableCanceled: onDraggableCanceled,
      onDragCompleted: onDragCompleted,
      child: child,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: _PointerDraggable<T>(
        data: data,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onDraggableCanceled: onDraggableCanceled,
        onDragCompleted: onDragCompleted,
        child: touch,
      ),
    );
  }
}

/// Picks a card up the moment a mouse button goes down and moves.
class _PointerDraggable<T extends Object> extends Draggable<T> {
  const _PointerDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    super.onDraggableCanceled,
    super.onDragCompleted,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    return _PointerRecognizer(allowedButtonsFilter: allowedButtonsFilter)..onStart = onStart;
  }
}

class _PointerRecognizer extends ImmediateMultiDragGestureRecognizer {
  _PointerRecognizer({super.allowedButtonsFilter});

  @override
  bool isPointerAllowed(PointerDownEvent event) => BoardDraggable.picksUpAtOnce(event.kind) && super.isPointerAllowed(event);
}

/// Picks a card up after a press and hold; a finger only (a mouse is the other one's).
class _TouchDraggable<T extends Object> extends LongPressDraggable<T> {
  const _TouchDraggable({
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
    super.onDraggableCanceled,
    super.onDragCompleted,
  });

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    return _TouchRecognizer(delay: delay, allowedButtonsFilter: allowedButtonsFilter)
      ..onStart = (Offset position) {
        final Drag? result = onStart(position);
        if (result != null && hapticFeedbackOnStart) HapticFeedback.selectionClick();
        return result;
      };
  }
}

class _TouchRecognizer extends DelayedMultiDragGestureRecognizer {
  _TouchRecognizer({super.delay, super.allowedButtonsFilter});

  @override
  bool isPointerAllowed(PointerDownEvent event) => !BoardDraggable.picksUpAtOnce(event.kind) && super.isPointerAllowed(event);
}
