import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/Competition.dart';

class OperationsCenterPage extends StatelessWidget {
  const OperationsCenterPage({super.key, required this.guideName});

  final String guideName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F2),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const _PreviewNotice(),
            const SizedBox(height: 18),
            Text(
              'Operations for $guideName',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                color: Color(0xFF24372C),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'College-aware planning with guide authority and HOD visibility.',
              style: TextStyle(color: Color(0xFF6C7770)),
            ),
            const SizedBox(height: 20),
            const _CalendarPulse(),
            const SizedBox(height: 20),
            const _SectionTitle('Active operations'),
            const SizedBox(height: 11),
            const _OperationCard(
              icon: Icons.directions_bus_filled_outlined,
              title: 'Rādhāṣṭamī · Ahmedabad',
              subtitle: 'Trip · 19 September · 34 interested',
              detail: 'Participant goals due one day before departure.',
              badge: '6 tasks',
              color: Color(0xFFB06D21),
            ),
            const _OperationCard(
              icon: Icons.auto_stories_outlined,
              title: 'Hostel RDUA circles',
              subtitle: 'SVNIT first year · daily evening pilot',
              detail: 'Two potential leaders; one trial circle pending.',
              badge: 'Attention',
              color: Color(0xFF315F45),
            ),
            _OperationCard(
              icon: Icons.emoji_events_outlined,
              title: 'Janmāṣṭamī challenge',
              subtitle: 'Hearing + chanting · customizable scoring',
              detail: 'Discount recommendations require guide approval.',
              badge: 'Draft',
              color: const Color(0xFF685390),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CompetitionPage()),
              ),
            ),
            const _OperationCard(
              icon: Icons.volunteer_activism_outlined,
              title: 'Service opportunity bank',
              subtitle: 'Design · coordination · prasādam support',
              detail: 'Match from natural guide conversation, not long forms.',
              badge: '4 open',
              color: Color(0xFF346D79),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Approvals and synchronization'),
            const SizedBox(height: 11),
            const _ApprovalPanel(),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AdminControlPage()),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open existing guide tools'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1CE),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Safe preview: no Trello card, notification, discount or student message is sent.',
          style: TextStyle(
            color: Color(0xFF795218),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _CalendarPulse extends StatelessWidget {
  const _CalendarPulse();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0xFFE3E7E1)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: Color(0xFF4F5FA8)),
                SizedBox(width: 9),
                Text(
                  'Calendar pressure · next 14 days',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            SizedBox(height: 14),
            _CohortPulse('SVNIT first year', 'Orientation', 'COOL DOWN'),
            _CohortPulse('IIIT Surat', 'Students available', 'PUSH'),
            _CohortPulse('Local colleges', 'Dates tentative', 'VERIFY'),
            Divider(height: 26),
            Text(
              'Student-reported calendar changes enter the guide approval queue before plans or reminders change.',
              style: TextStyle(
                color: Color(0xFF68736C),
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _CohortPulse extends StatelessWidget {
  const _CohortPulse(this.cohort, this.reason, this.mode);
  final String cohort;
  final String reason;
  final String mode;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cohort,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(reason,
                      style: const TextStyle(
                          color: Color(0xFF7A857E), fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFFC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                mode,
                style: const TextStyle(
                  color: Color(0xFF4F5FA8),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Color(0xFF24372C),
        ),
      );
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.badge,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final String badge;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(19),
          side: const BorderSide(color: Color(0xFFE3E7E1)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF6C7770), fontSize: 11)),
                      const SizedBox(height: 8),
                      Text(detail,
                          style: const TextStyle(
                              color: Color(0xFF4E5D54),
                              fontSize: 12,
                              height: 1.35)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EAF6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3 guide approvals pending',
              style: TextStyle(
                color: Color(0xFF4E345E),
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 9),
            Text(
              '2 trip discounts · 1 calendar correction',
              style: TextStyle(color: Color(0xFF685277)),
            ),
            Divider(height: 25),
            Row(
              children: [
                Icon(Icons.view_kanban_outlined,
                    size: 19, color: Color(0xFF744F8E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trello: mock mode · 0 real cards sent',
                    style: TextStyle(
                      color: Color(0xFF5D4968),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
