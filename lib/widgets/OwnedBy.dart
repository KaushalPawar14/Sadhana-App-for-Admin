import 'package:flutter/widgets.dart';

/// Hands a dialog's or sheet's text controllers (or focus nodes) to the dialog itself.
///
/// The way these were disposed was `await showDialog(...)` and then `controller.dispose()` on the next line. But the
/// future of `showDialog` / `showModalBottomSheet` completes when the pop STARTS, not when the route has left: for
/// the next ~200 ms the dialog is still sliding away, still painting its fields — and the phone's back button also
/// closes the keyboard in that window, which rebuilds them. A field built on a disposed controller is the full red
/// error screen ("A TextEditingController was used after being disposed").
///
/// Wrap the builder instead: `builder: ownedBy([nameController], (context) { ... })`. The controllers are disposed
/// when the dialog's widgets are removed from the tree for good — after the exit animation, and after the fields
/// that use them have gone (children are unmounted before their parent).
WidgetBuilder ownedBy(List<ChangeNotifier> owned, WidgetBuilder builder) =>
    (context) => _Owner(owned: owned, child: Builder(builder: builder));

class _Owner extends StatefulWidget {
  const _Owner({required this.owned, required this.child});

  final List<ChangeNotifier> owned;
  final Widget child;

  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    for (final c in widget.owned) {
      c.dispose();
    }
    super.dispose();
  }
}
