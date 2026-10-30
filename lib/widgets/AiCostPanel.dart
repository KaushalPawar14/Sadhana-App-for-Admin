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

/// The Student app's AI, in the order the view lists it (the keys are the server's).
const Map<String, String> kStudentAiTypes = {
  'studentChat': 'Student chat',
  'studentDaily': 'Daily messages',
  'studentWeb': 'Web answers',
};

/// The estimated credit left in the OpenAI account (the server works it out: `creditView` in `functions/aiUsage.js`).
class AiCredit {
  const AiCredit({
    this.hasTopups = false,
    this.topups = const [],
    this.topupInr = 0,
    this.topupUsd = 0,
    this.spentInr = 0,
    this.spentUsd = 0,
    this.remainingInr = 0,
    this.remainingUsd = 0,
    this.leftPct = 0,
    this.low = false,
    this.out = false,
    this.perDayInr = 0,
    this.daysLeft,
    this.usdInr = 88,
    this.failed = false,
  });

  /// The server could not work the estimate out (shown as a plain line, never a crash).
  final bool failed;
  final bool hasTopups;
  final List<AiTopup> topups;
  final double topupInr, topupUsd, spentInr, spentUsd, remainingInr, remainingUsd, leftPct, perDayInr, usdInr;
  final bool low, out;

  /// Days of credit left at the current rate; null when nothing has been spent lately (no estimate).
  final int? daysLeft;

  static double _d(Object? v) => v is num ? v.toDouble() : 0;

  static AiCredit fromMap(Map<String, dynamic> m) => AiCredit(
        hasTopups: m['hasTopups'] == true,
        topups: [
          if (m['topups'] is List)
            for (final t in m['topups'] as List)
              if (t is Map) AiTopup(id: (t['id'] ?? '').toString(), date: (t['date'] ?? '').toString(), usd: _d(t['usd']), inr: _d(t['inr'])),
        ],
        topupInr: _d(m['topupInr']),
        topupUsd: _d(m['topupUsd']),
        spentInr: _d(m['spentInr']),
        spentUsd: _d(m['spentUsd']),
        remainingInr: _d(m['remainingInr']),
        remainingUsd: _d(m['remainingUsd']),
        leftPct: _d(m['leftPct']),
        low: m['low'] == true,
        out: m['out'] == true,
        perDayInr: _d(m['perDayInr']),
        daysLeft: m['daysLeft'] is num ? (m['daysLeft'] as num).round() : null,
        usdInr: m['usdInr'] is num ? (m['usdInr'] as num).toDouble() : 88,
      );
}

class AiTopup {
  const AiTopup({required this.id, required this.date, required this.usd, required this.inr});
  final String id, date;
  final double usd, inr;
}

/// "$5.00" (the figures of the credit view).
String usd(num v) => '\$${v.toStringAsFixed(2)}';

/// THE HOD'S AI COST VIEW (inside the Assistant log): this month's total against the budget, today's total, and the breakdown per guide
/// and per type, for a month and (optionally) one guide; the STUDENT APP's AI (student chat, daily messages, web answers) beside it, the last
/// seven days, and the CREDIT TOP-UPS with the estimated remaining credit. HODs only: the server's rules deny every other admin, and this panel is only
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
  /// The last seven days' totals (for "Last 7 days").
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _week = GuideDb.instance
      .collection('aiUsageDays')
      .where('day', isGreaterThanOrEqualTo: istDay((widget.now ?? DateTime.now()).subtract(const Duration(days: 6))))
      .snapshots();
  bool _busy = false;

  /// The estimated remaining credit (the server works it out; reloaded when a top-up changes or today's spending moves).
  Future<AiCredit>? _credit;
  double _lastTodayTotal = -1;

  Future<AiCredit> _loadCredit() async {
    try {
      return AiCredit.fromMap(await HierarchyApi.instance.aiCreditView());
    } catch (_) {
      return const AiCredit(failed: true);
    }
  }

  void _reloadCredit() {
    if (!mounted) return;
    final next = _loadCredit();
    setState(() {
      _credit = next;
    });
  }

  @override
  void initState() {
    super.initState();
    _credit = _loadCredit();
  }

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

  /// ADD A TOP-UP: the date, the amount in US$ and in ₹ (₹ left empty: US$ times the rate).
  Future<void> _addTopup(AiCredit c) async {
    final entered = await showDialog<({String date, String usd, String inr})>(
      context: context,
      builder: (ctx) => _TopupDialog(today: istDay(widget.now ?? DateTime.now()), rate: c.usdInr),
    );
    if (entered == null || !mounted) return;
    final u = double.tryParse(entered.usd);
    final r = entered.inr.isEmpty ? null : double.tryParse(entered.inr);
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the amount in US dollars.')));
      return;
    }
    await _run(() => HierarchyApi.instance.addAiTopup(date: entered.date, usd: u, inr: r), 'Top-up saved');
    _reloadCredit();
  }

  Future<void> _deleteTopup(AiTopup t) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => GuideDialog(
        title: const Text('Remove this top-up?'),
        content: Text('${t.date}: ${usd(t.usd)} / ${inr(t.inr)}. Do this only for an entry made by mistake.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(key: const ValueKey('ai-topup-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(() => HierarchyApi.instance.deleteAiTopup(t.id), 'Top-up removed');
    _reloadCredit();
  }

  /// CREDIT TOP-UPS: the estimated remaining credit (top-ups minus everything tracked), a warning at 20% left, the days left at the current rate,
  /// the list of top-ups and the button to add one.
  Widget _creditCard(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return FutureBuilder<AiCredit>(
      future: _credit,
      builder: (context, snap) {
        final c = snap.data;
        return Padding(
          key: const ValueKey('ai-credit-panel'),
          padding: const EdgeInsets.only(bottom: 14),
          child: GuideCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Credit top-ups', style: t.cardTitleSmall),
                const SizedBox(height: 2),
                Text('Enter each top-up of the OpenAI account. The estimate is the top-ups minus everything the AI has cost since the first one (guides and students).', style: t.caption),
                const SizedBox(height: 10),
                if (snap.hasError || (c?.failed ?? false))
                  Text("Couldn't work out the credit.", key: const ValueKey('ai-credit-error'), style: t.small)
                else if (c == null)
                  const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (!c.hasTopups)
                  Text('No top-up entered yet. Add one to see the estimated credit left.', key: const ValueKey('ai-credit-none'), style: t.small)
                else ...[
                  Text('Estimated credit left: ${inr(c.remainingInr)} (${usd(c.remainingUsd)})', key: const ValueKey('ai-credit-left'), style: t.bodyStrong),
                  const SizedBox(height: 6),
                  GuideProgressBar(key: const ValueKey('ai-credit-bar'), value: c.leftPct.clamp(0.0, 1.0), height: 8),
                  const SizedBox(height: 4),
                  Text('Top-ups ${inr(c.topupInr)} (${usd(c.topupUsd)}) − spent ${inr(c.spentInr)} (${usd(c.spentUsd)})', key: const ValueKey('ai-credit-math'), style: t.caption),
                  if (c.out)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('The credit is used up (by this estimate). Add a top-up, or the AI will stop working.', key: const ValueKey('ai-credit-out'), style: t.small.copyWith(color: g.danger, fontWeight: FontWeight.w600)),
                    )
                  else if (c.low)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Only ${(c.leftPct * 100).round()}% of the credit is left. Top up soon.', key: const ValueKey('ai-credit-low'), style: t.small.copyWith(color: g.danger, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    c.daysLeft == null ? 'No spending lately, so no estimate of the days left.' : 'At the current rate (${inr(c.perDayInr)} a day), about ${c.daysLeft} day${c.daysLeft == 1 ? '' : 's'} left.',
                    key: const ValueKey('ai-credit-days'),
                    style: t.small,
                  ),
                  const SizedBox(height: 10),
                  Text('Top-ups', style: t.bodyStrong),
                  for (final tp in c.topups)
                    Row(
                      key: ValueKey('ai-topup-${tp.id}'),
                      children: [
                        Expanded(child: Text('${tp.date}   ${usd(tp.usd)}   ${inr(tp.inr)}', style: t.small)),
                        IconButton(key: ValueKey('ai-topup-delete-${tp.id}'), tooltip: 'Remove this top-up', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _deleteTopup(tp)),
                      ],
                    ),
                ],
                const SizedBox(height: 8),
                OutlinedButton(key: const ValueKey('ai-topup-add'), onPressed: _busy ? null : () => _addTopup(c ?? const AiCredit()), child: const Text('Add top-up')),
              ],
            ),
          ),
        );
      },
    );
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
          builder: (context, todaySnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _week,
          builder: (context, weekSnap) {
            if (sumSnap.hasError) {
              return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text("Couldn't load the AI costs (${sumSnap.error}).", key: const ValueKey('ai-cost-error'), style: t.small));
            }
            final budget = _n(budgetSnap.data?.data()?['monthlyInr']) > 0 ? _n(budgetSnap.data!.data()!['monthlyInr']) : 1000.0;
            final overridden = (budgetSnap.data?.data()?['overrideMonth'] ?? '') == widget.month;
            bool isStudentRow(Map<String, dynamic> r) => r['scope'] == 'student' || r['adminId'] == 'student-app';
            final everyRow = (sumSnap.data?.docs ?? const []).map((d) => d.data()).toList()..sort((a, b) => _n(b['total']).compareTo(_n(a['total'])));
            // the guides' rows (the budget and the guide filter) and the Student app's row (shown beside them, never part of the budget)
            final rows = everyRow.where((r) => !isStudentRow(r)).toList();
            final studentRows = everyRow.where(isStudentRow).toList();
            final studentTotal = studentRows.fold<double>(0, (s, r) => s + _n(r['total']));
            final studentByType = {for (final k in kStudentAiTypes.keys) k: studentRows.fold<double>(0, (s, r) => s + _n(r['t_$k']))};
            final allTotal = rows.fold<double>(0, (s, r) => s + _n(r['total']));
            final shown = widget.guide == null ? rows : rows.where((r) => r['adminId'] == widget.guide).toList();
            final shownTotal = shown.fold<double>(0, (s, r) => s + _n(r['total']));
            final byType = {for (final k in kAiTypes.keys) k: shown.fold<double>(0, (s, r) => s + _n(r['t_$k']))};
            final pct = budget == 0 ? 0.0 : allTotal / budget;
            final isThisMonth = widget.month == istMonth(widget.now ?? DateTime.now());
            final today = todaySnap.data?.data();
            final todayTotal = today == null ? 0.0 : (widget.guide == null ? _n(today['total']) : _n(today['a_${widget.guide}']));
            final todayStudents = today == null || widget.guide != null ? 0.0 : _n(today['s_total']);
            // the credit estimate follows today's spending
            final spendNow = today == null ? 0.0 : _n(today['total']);
            if (todaySnap.hasData && spendNow != _lastTodayTotal) {
              if (_lastTodayTotal >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _reloadCredit());
              _lastTodayTotal = spendNow;
            }
            final days = (weekSnap.data?.docs ?? const []).map((d) => d.data()).toList()..sort((a, b) => (b['day'] ?? '').toString().compareTo((a['day'] ?? '').toString()));
            final paused = pct >= 1 && !overridden && isThisMonth;

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
              key: const ValueKey('ai-cost-panel'),
              padding: const EdgeInsets.only(bottom: 14),
              child: GuideCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI cost', style: t.cardTitleSmall),
                    const SizedBox(height: 2),
                    Text('Everything the AI used: the guides\' (assistant, plans and questions, voice, interaction analysis, target plans) and the Student app\'s (student chat, daily messages, web answers).', style: t.caption),
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
                    if (widget.guide == null) ...[
                      const SizedBox(height: 6),
                      Text('Student app: ${inr(studentTotal)}', key: const ValueKey('ai-cost-student-total'), style: t.small),
                      Text('All AI spending: ${inr(allTotal + studentTotal)}', key: const ValueKey('ai-cost-grand-total'), style: t.bodyStrong),
                    ],
                    if (isThisMonth) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Today${widget.guide == null ? '' : ' (this guide)'}: ${inr(todayTotal)}${todayStudents > 0 ? ' (guides ${inr(todayTotal - todayStudents)}, students ${inr(todayStudents)})' : ''}',
                        key: const ValueKey('ai-cost-today'),
                        style: t.small,
                      ),
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
                    if (widget.guide == null) ...[
                      const SizedBox(height: 10),
                      Text('Student app', style: t.bodyStrong),
                      const SizedBox(height: 4),
                      for (final e in kStudentAiTypes.entries)
                        Padding(
                          key: ValueKey('ai-cost-type-${e.key}'),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Expanded(child: Text(e.value, style: t.small)),
                            Text(inr(studentByType[e.key] ?? 0), style: t.small.copyWith(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                    ],
                    const SizedBox(height: 10),
                    Text(widget.guide == null ? 'Last 7 days' : 'Last 7 days (this guide)', style: t.bodyStrong),
                    const SizedBox(height: 4),
                    if (days.isEmpty) Text('No AI use in the last 7 days.', key: const ValueKey('ai-cost-days-none'), style: t.small),
                    for (final d in days)
                      Padding(
                        key: ValueKey('ai-cost-day-${d['day']}'),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Expanded(child: Text(widget.guide == null && _n(d['s_total']) > 0 ? '${d['day']}  (students ${inr(_n(d['s_total']))})' : '${d['day']}', style: t.small)),
                          Text(inr(widget.guide == null ? _n(d['total']) : _n(d['a_${widget.guide}'])), style: t.small.copyWith(fontWeight: FontWeight.w600)),
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
            ),
              _creditCard(context),
            ]);
          }),
        ),
      ),
    );
  }
}

/// The small dialog of a new top-up. It owns its text fields, so they are disposed only when the dialog is gone.
class _TopupDialog extends StatefulWidget {
  const _TopupDialog({required this.today, required this.rate});

  final String today;
  final double rate;

  @override
  State<_TopupDialog> createState() => _TopupDialogState();
}

class _TopupDialogState extends State<_TopupDialog> {
  late final TextEditingController _date = TextEditingController(text: widget.today);
  final TextEditingController _usd = TextEditingController();
  final TextEditingController _inr = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _usd.dispose();
    _inr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GuideDialog(
      title: const Text('Add a credit top-up'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const ValueKey('ai-topup-date'), controller: _date, decoration: const InputDecoration(labelText: 'Date (yyyy-mm-dd)')),
          TextField(key: const ValueKey('ai-topup-usd'), controller: _usd, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: 'US\$ ', labelText: 'Amount in US dollars')),
          TextField(
            key: const ValueKey('ai-topup-inr'),
            controller: _inr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: '₹ ', labelText: 'Amount in rupees', helperText: 'Left empty: dollars × ₹${widget.rate.round()}'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          key: const ValueKey('ai-topup-save'),
          onPressed: () => Navigator.pop(context, (date: _date.text.trim(), usd: _usd.text.trim(), inr: _inr.text.trim())),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
