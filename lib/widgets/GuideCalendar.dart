import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../utils/CalendarQueries.dart';
import '../theme/GuideTokens.dart';
import 'GuideSurface.dart';

/// The calendar category of an event, for its colour: an exam, festival or
/// programme by its `type`; any other event by its scope (a mandatory one is
/// "Mandatory", a personal one "Personal").
GuideEventType guideEventTypeOf(CalendarEvent e) {
  switch (e.type) {
    case kEventTypeExam:
      return GuideEventType.exam;
    case kEventTypeFestival:
      return GuideEventType.festival;
    case kEventTypeProgram:
      return GuideEventType.program;
    default:
      return e.isMandatory ? GuideEventType.mandatory : GuideEventType.personal;
  }
}

String guideEventTypeLabel(CalendarEvent e) {
  switch (e.type) {
    case kEventTypeExam:
    case kEventTypeFestival:
    case kEventTypeProgram:
      return kEventTypeLabels[e.type]!;
    default:
      return e.isMandatory ? 'Mandatory' : 'Personal';
  }
}

/// The text scale the grid is laid out for (never below 1).
double _scaleOf(BuildContext context) =>
    math.max(1.0, MediaQuery.textScalerOf(context).scale(15) / 15);

/// Size of the date circle for a cell [cellWidth] wide: 32 dp, growing with the
/// text size so a large date number is never clipped.
double guideDayCircle(BuildContext context, double cellWidth) =>
    math.min(cellWidth - 2, math.max(32.0, 15 * _scaleOf(context) * 1.55));

/// The height of one week row: the circle zone plus the dots row. A MINIMUM that
/// grows with the text size.
double guideCalendarRowHeight(BuildContext context, double cellWidth) =>
    guideDayCircle(context, cellWidth) + 8 + 14;

/// One day of the month grid.
///
/// * a soft rounded band behind the dates of a multi-day exam / festival /
///   programme (rounded at the first and last day, square where it continues
///   across a week break); bands that overlap on a day stack, at most three;
/// * the date number, in a brass-gradient circle when selected (a brass ring when
///   it is today);
/// * under it, one dot per event in the event's own colour: at most three, then a
///   small "+" when there are more. A band event also keeps its dot, so overlapping
///   events are never hidden.
class GuideDayCell extends StatelessWidget {
  const GuideDayCell({
    super.key,
    required this.day,
    required this.events,
    required this.cellWidth,
    this.selected = false,
    this.isToday = false,
    this.outside = false,
  });

  final DateTime day;

  /// Every event that covers [day] (single- and multi-day).
  final List<CalendarEvent> events;
  final double cellWidth;
  final bool selected;
  final bool isToday;
  final bool outside;

  static bool hasBand(GuideEventType t) =>
      t == GuideEventType.exam || t == GuideEventType.festival || t == GuideEventType.program;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final circle = guideDayCircle(context, cellWidth);
    final zone = circle + 8;
    final height = guideCalendarRowHeight(context, cellWidth);

    final bands = [
      for (final e in events)
        if (e.isMultiDay && hasBand(guideEventTypeOf(e))) e,
    ]..sort((a, b) {
        final byStart = a.eventDate.compareTo(b.eventDate);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final shown = bands.take(3).toList();
    final bandZone = circle + 4;
    final bandHeight = shown.isEmpty ? 0.0 : bandZone / shown.length;

    final dots = events.take(3).toList();
    final more = events.length > 3;
    final dayStyle = t.body.copyWith(
      fontSize: 15,
      fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w400,
      color: selected
          ? g.onPrimary
          : (outside ? g.mutedText.withValues(alpha: .45) : g.text),
    );

    return SizedBox(
      width: cellWidth,
      height: height,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              top: (zone - bandZone) / 2 + i * bandHeight,
              left: 0,
              right: 0,
              height: bandHeight,
              child: _band(context, shown[i], bandHeight),
            ),
          Positioned(
            top: (zone - circle) / 2,
            child: GuideSelectPop(
              selected: selected,
              child: Container(
                width: circle,
                height: circle,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? g.primaryGradient : null,
                  border: isToday && !selected ? Border.all(color: g.brass, width: 1.5) : null,
                  boxShadow: selected
                      ? [BoxShadow(color: g.brassGlow, blurRadius: 14, offset: const Offset(0, 6))]
                      : null,
                ),
                child: Text('${day.day}', style: dayStyle),
              ),
            ),
          ),
          if (dots.isNotEmpty)
            Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < dots.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: g.eventColor(guideEventTypeOf(dots[i])),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  if (more) ...[
                    const SizedBox(width: 3),
                    Text('+',
                        style: TextStyle(
                            fontSize: 9,
                            height: .8,
                            fontWeight: FontWeight.w700,
                            color: g.mutedText)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _band(BuildContext context, CalendarEvent e, double height) {
    final g = context.g;
    final isStart = isSameCalendarDay(day, e.eventDate);
    final isEnd = isSameCalendarDay(day, e.effectiveEndDate);
    final cap = Radius.circular(height / 2);
    // How many days into the event this cell is: later days start growing later,
    // so the band reads as growing from its first day.
    final offset = day.difference(DateTime(e.eventDate.year, e.eventDate.month, e.eventDate.day)).inDays;
    return GuideBandGrow(
      order: offset.clamp(0, 6),
      child: Container(
        margin: EdgeInsetsDirectional.only(start: isStart ? 2 : 0, end: isEnd ? 2 : 0),
        decoration: BoxDecoration(
          color: g.eventBand(guideEventTypeOf(e)),
          borderRadius: BorderRadius.horizontal(
            left: isStart ? cap : Radius.zero,
            right: isEnd ? cap : Radius.zero,
          ),
        ),
      ),
    );
  }
}

/// A date that becomes selected scales in from 0.6 to 1 (150 ms). The circle is
/// always laid out at full size; only the paint scales.
class GuideSelectPop extends StatefulWidget {
  const GuideSelectPop({super.key, required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<GuideSelectPop> createState() => _GuideSelectPopState();
}

class _GuideSelectPopState extends State<GuideSelectPop> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _playing = false;

  void _play() {
    if (GuideMotion.reduced(context)) return;
    final c = _controller ??=
        AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _playing = true;
    c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.selected && _controller == null) _play();
  }

  @override
  void didUpdateWidget(GuideSelectPop old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !_playing || !widget.selected) return widget.child;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.6, end: 1).animate(CurvedAnimation(parent: c, curve: GuideMotion.out)),
      child: widget.child,
    );
  }
}

/// A multi-day band grows from its left edge in 200 ms; the later the day within the
/// event, the later it starts (20 ms a day, at most six days). Plays once per cell.
class GuideBandGrow extends StatefulWidget {
  const GuideBandGrow({super.key, required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  State<GuideBandGrow> createState() => _GuideBandGrowState();
}

class _GuideBandGrowState extends State<GuideBandGrow> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _curve;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (GuideMotion.reduced(context)) return;
    final delay = Duration(milliseconds: 20 * widget.order);
    final total = const Duration(milliseconds: 200) + delay;
    final c = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: c,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: GuideMotion.out),
    );
    _controller = c
      ..forward().whenComplete(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || c.isCompleted) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: _curve.value.clamp(0.0, 1.0), child: child),
      ),
    );
  }
}

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The compact legend above the month: a dot for Mandatory and Personal, a band
/// swatch for Exam, Festival and Programme (11 px muted labels).
class GuideCalendarLegend extends StatelessWidget {
  const GuideCalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;

    Widget entry(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 5),
            Text(label, style: t.caption.copyWith(fontSize: 11)),
          ],
        );
    Widget dot(Color c) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    Widget band(Color c) => Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        entry(dot(g.eventMandatory), 'Mandatory'),
        entry(dot(g.eventPersonal), 'Personal'),
        entry(band(g.bandExam), 'Exam'),
        entry(band(g.bandFestival), 'Festival'),
        entry(band(g.bandProgram), 'Program'),
      ],
    );
  }
}

/// One event of the selected day: a colour bar, the title, "Type · date range" and
/// a chevron (an edit affordance when the viewer may change it). The whole row is
/// the tap target.
class GuideEventRow extends StatelessWidget {
  const GuideEventRow({super.key, required this.event, this.onTap});

  final CalendarEvent event;

  /// Null = read-only.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    final kind = guideEventTypeOf(event);
    final range = event.isMultiDay
        ? '${DateFormat('dd').format(event.eventDate)} – ${DateFormat('dd MMM').format(event.effectiveEndDate)}'
        : DateFormat('dd MMM').format(event.eventDate);
    final card = GuideCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: g.eventColor(kind),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(event.title.isEmpty ? '(untitled)' : event.title,
                      style: t.cardTitleSmall),
                  const SizedBox(height: 2),
                  Text('${guideEventTypeLabel(event)} · $range', style: t.caption),
                  if (event.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(event.note, style: t.caption.copyWith(color: g.text.withValues(alpha: .75))),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: g.mutedText),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: onTap != null,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card),
      ),
    );
  }
}
