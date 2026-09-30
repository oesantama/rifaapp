import 'package:flutter/material.dart';

/// Child of a [Flex] that switches between horizontal (wide) and vertical (phone):
/// it expands to share the row on wide screens and takes its natural height when
/// stacked, where an [Expanded] would fail inside a scroll view.
class ResponsiveFlexChild extends StatelessWidget {
  final bool expand;
  final int flex;
  final Widget child;

  const ResponsiveFlexChild({super.key, required this.expand, this.flex = 1, required this.child});

  @override
  Widget build(BuildContext context) {
    return expand ? Expanded(flex: flex, child: child) : child;
  }
}

/// Phone-sized width, where side-by-side form fields are stacked instead.
bool isNarrowScreen(BuildContext context) => MediaQuery.sizeOf(context).width < 600;
