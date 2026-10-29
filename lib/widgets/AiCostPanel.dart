import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../Services/HierarchyApi.dart';
import '../theme/GuideTheme.dart';
import '../utils/GuideDb.dart';
import 'GuideDialog.dart';
import 'GuideSurface.dart';
import 'GuideTiles.dart';

/// "₹3.52" under ₹100, "₹842" from ₹100 (the figures of the AI cost view).
String inr(num v) => v >= 100 ? '₹${v.round()}' : '₹${v.toStringAsFixed(2)}';

/// The month a date falls in, in India, as `yyyy-MM`.
String istMonth(DateTime t) => t.toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 7);
String istDay(DateTime t) => t.toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);

/// The kinds of AI work the guide side uses, in the order the view lists them (the keys are the server's, `functions/aiUsage.js`).
const Map<String, String> kAiTypes = {
  'assistant': 'Assistant tasks',
  'plans': 'Plans and questions',
  'voice': 'Voice to text',
  'analysis': 'Interaction analysis',
  'targetPlan': 'Target plans',
  'other': 'Other',
};

/// THE HOD'S AI COST VIEW (inside the Assistant log): this month's total against the budget, today's total, and the breakdown per guide
/// and per type, for a month and (optionally) one guide. HODs only: the server's rules deny every other admin, and this panel is only
/// ever built for a HOD (`AgentLogPage` is HOD-only).
///
/// Everything the guides' AI used is in these totals (assistant, plans and questions, voice, interaction analysis, target plans, other),
/// not only the chats listed below.
class AiCostPanel extends StatefulWidget {
  const AiCostPanel({super.key, required this.month, required this.guide, required this.onMonth, required this.onGuide, this.now});

  final String month;
  final String? guide;
  final ValueChanged<String> onMonth;
  final ValueChanged<String?> onGuide;

  /// The clock (tests).
  final DateTime? now;

  @override
  State<AiCostPanel> createState() => _AiCostPanelState();
}

class _AiCostPanelState extends State<AiCostPanel> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sums = _sumsFor(widget.month);
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _budget = GuideDb.instance.collection('aiBudget').doc('current').snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _today = GuideDb.instance.collection('aiUsageDays').doc(istDay(widget.now ?? DateTime.now())).snapshots();
  bool _busy = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _sumsFor(String m) => GuideDb.instance.collection('aiUsageSummary').where('month', isEqualTo: m).snapshots();

  @override
  void didUpdateWidget(AiCostPanel old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month) _sums = _sumsFor(widget.month);
  }

  /// This month and the five before it.
  List<String> get _months {
    final now = widget.now ?? DateTime.now();
    var y = int.parse(istMonth(now).substring(0, 4));
    var m = int.parse(istMonth(now).substring(5, 7));
    final out = <String>[];
    for (var i = 0; i < 6; i++) {
      out.add('$y-${m.toString().padLeft(2, '0')}');
      m--;
      if (m == 0) {
        m = 12;
        y--;
      }
    }
    return out;
  }

  static String _monthName(String ym) {
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${names[int.parse(ym.substring(5, 7)) - 1]} ${ym.substring(0, 4)}';
  }

  double _n(Object? v) => v is num ? v.toDouble() : 0;

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is HierarchyException ? e.message : 'Could not do that. Please try again.')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changeBudget(double current) async {
    final controller = TextEditingController(text: current.round().toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => GuideDialog(
        title: const Text('Monthly AI budget'),
        content: TextField(key: const ValueKey('ai-budget-field'), controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ', helperText: 'For all the guides together, per month')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(key: const ValueKey('ai-budget-save'), onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (value == null) return;
    await _run(() => HierarchyApi.instance.setAiBudget(monthlyInr: value), 'Budget saved: ${inr(value)} a month');
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sums,
      builder: (context, sumSnap) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _budget,
        builder: (context, budgetSnap) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _today,
          builder: (context, todaySnap) {
            if (sumSnap.hasError) {
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text("Couldn't load the AI costs (${sumSnap.error}).", key: const ValueKey('ai-cost-error'), style: t.small));
            }
            final budget = _n(budgetSnap.data?.data()?['monthlyInr']) > 0 ? _n(budgetSnap.data!.data()!['monthlyInr']) : 1000.0;
            final overridden = (budgetSnap.data?.data()?['overrideMonth'] ?? '') == widget.month;
            final rows = (sumSnap.data?.docs ?? const []).map((d) => d.data()).toList()..sort((a, b) => _n(b['total']).compareTo(_n(a['total'])));
            final allTotal = rows.fold<double>(0, (s, r) => s + _n(r['total']));
            final shown = widget.guide == null ? rows : rows.where((r) => r['adminId'] == widget.guide).toList();
            final shownTotal = shown.fold<double>(0, (s, r) => s + _n(r['total']));
            final byType = {for (final k in kAiTypes.keys) k: shown.fold<double>(0, (s, r) => s + _n(r['t_$k']))};
            final pct = budget == 0 ? 0.0 : allTotal / budget;
            final isThisMonth = widget.month == istMonth(widget.now ?? DateTime.now());
            final today = todaySnap.data?.data();
            final todayTotal = today == null ? 0.0 : (widget.guide == null ? _n(today['total']) : _n(today['a_${widget.guide}']));
            final paused = pct >= 1 && !overridden && isThisMonth;

            return Padding(
              key: const ValueKey('ai-cost-panel'),
              padding: const EdgeInsets.only(bottom: 14),
              child: GuideCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI cost', style: t.cardTitleSmall),
                    const SizedBox(height: 2),
                    Text('Everything the guides\' AI used: assistant, plans and questions, voice, interaction analysis, target plans.', style: t.caption),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DropdownButton<String>(
                          key: const ValueKey('ai-cost-month'),
                          value: _months.contains(widget.month) ? widget.month : _months.first,
                          items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(_monthName(m)))],
                          onChanged: (m) => m == null ? null : widget.onMonth(m),
                        ),
                        DropdownButton<String?>(
                          key: const ValueKey('ai-cost-guide'),
                          value: rows.any((r) => r['adminId'] == widget.guide) ? widget.guide : null,
                          hint: const Text('All guides'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('All guides')),
                            for (final r in rows) DropdownMenuItem<String?>(value: r['adminId'] as String?, child: Text((r['adminName'] ?? r['adminId'] ?? '?').toString())),
                          ],
                          onChanged: widget.onGuide,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('${_monthName(widget.month)}: ${inr(allTotal)} of ${inr(budget)} (${(pct * 100).round()}%)', key: const ValueKey('ai-cost-month-total'), style: t.bodyStrong),
                    const SizedBox(height: 6),
                    GuideProgressBar(key: const ValueKey('ai-cost-bar'), value: pct.clamp(0.0, 1.0), height: 8),
                    if (pct >= 0.8 && pct < 1) Padding(padding: const EdgeInsets.only(top: 4), child: Text('80% of the budget is used. At 100% the AI pauses until next month.', key: const ValueKey('ai-cost-warn'), style: t.caption.copyWith(color: g.warning))),
                    if (paused) ...[
                      const SizedBox(height: 6),
                      Text("This month's AI budget is used up: the AI is paused until next month.", key: const ValueKey('ai-cost-paused'), style: t.small.copyWith(color: g.danger, fontWeight: FontWeight.w600)),
                    ],
                    if (overridden && isThisMonth) Padding(padding: const EdgeInsets.only(top: 4), child: Text('A HOD resumed the AI for this month.', key: const ValueKey('ai-cost-resumed'), style: t.caption)),
                    if (isThisMonth) ...[
                      const SizedBox(height: 6),
                      Text('Today${widget.guide == null ? '' : ' (this guide)'}: ${inr(todayTotal)}', key: const ValueKey('ai-cost-today'), style: t.small),
                    ],
                    const SizedBox(height: 12),
                    Text(widget.guide == null ? 'By guide' : 'This guide', style: t.bodyStrong),
                    const SizedBox(height: 4),
                    if (shown.isEmpty) Text('No AI use recorded yet.', key: const ValueKey('ai-cost-none'), style: t.small),
                    for (final r in shown)
                      Padding(
                        key: ValueKey('ai-cost-guide-${r['adminId']}'),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Expanded(child: Text((r['adminName'] ?? r['adminId'] ?? '?').toString(), style: t.small)),
                          Text(inr(_n(r['total'])), style: t.small.copyWith(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    const SizedBox(height: 10),
                    Text(widget.guide == null ? 'By kind of work' : 'By kind of work (this guide)', style: t.bodyStrong),
                    const SizedBox(height: 4),
                    for (final e in kAiTypes.entries)
                      Padding(
                        key: ValueKey('ai-cost-type-${e.key}'),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Expanded(child: Text(e.value, style: t.small)),
                          Text(inr(byType[e.key] ?? 0), style: t.small.copyWith(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    if (widget.guide != null && shown.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Guide total: ${inr(shownTotal)}', key: const ValueKey('ai-cost-guide-total'), style: t.small.copyWith(fontWeight: FontWeight.w600))),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      OutlinedButton(key: const ValueKey('ai-budget-change'), onPressed: _busy ? null : () => _changeBudget(budget), child: const Text('Change budget')),
                      if (paused) FilledButton(key: const ValueKey('ai-budget-resume'), onPressed: _busy ? null : () => _run(() => HierarchyApi.instance.resumeAiForMonth(), 'The AI is back for this month'), child: const Text('Resume this month')),
                    ]),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
