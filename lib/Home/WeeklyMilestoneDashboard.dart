import 'package:flutter/material.dart';
import 'package:folk_guide_app/Pages/Competition.dart';
import 'package:folk_guide_app/Pages/StudentJourneyProfile.dart';
import 'package:folk_guide_app/Services/AssignedStudentRepository.dart';
import 'package:folk_guide_app/Services/FolkIdentityService.dart';
import 'package:folk_guide_app/config/AppConfiguration.dart';

class WeeklyMilestoneDashboard extends StatelessWidget {
  const WeeklyMilestoneDashboard({super.key, required this.guideName});

  final String guideName;

  static const metrics = [
    _QuarterMetric('Chanting 4–7 rounds', 12, 20, '8 students remaining'),
    _QuarterMetric('Q1 book journey', 9, 50, 'Prioritize paused readers'),
    _QuarterMetric('FOLK–2 completed', 11, 50, '6 near completion'),
    _QuarterMetric('Association minutes', 1540, 6250, '375-minute weekly goal'),
  ];

  static const focusStudents = [
    _FocusStudent(
        'Aarav P.',
        'SVNIT · First year',
        'Reading stopped after chapter 2',
        'Personalized book motivation + hostel meeting',
        'Tue'),
    _FocusStudent(
        'Harsh M.',
        'IIIT Surat · First year',
        'No personal association for 19 days',
        'Offer two video-call slots',
        'Wed'),
    _FocusStudent('Manav S.', 'Local · SCET', 'Ready for a bounded seva',
        'Offer competition design service', 'Thu'),
    _FocusStudent(
        'Rohan K.',
        'SVNIT · Second year',
        'Potential RDUA student leader',
        'Invite him to one trial circle',
        'Thu'),
  ];

  @override
  Widget build(BuildContext context) {
    final liveAssignmentsEnabled = AppConfiguration.readsSupabase &&
        FolkIdentityService.currentUser != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F2),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF1CE),
                  borderRadius: BorderRadius.circular(16)),
              child: Text(
                liveAssignmentsEnabled
                    ? 'Private test mode: assigned-student pulse is live from Supabase; planning targets below remain representative.'
                    : 'Prototype with representative students. Sign in to the Supabase test mode for assigned-student data.',
                style: const TextStyle(
                    color: Color(0xFF795218),
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Text('Hare Krishna, $guideName',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF21362A))),
            const SizedBox(height: 4),
            const Text('Monday plan · 10–16 August 2026',
                style: TextStyle(
                    color: Color(0xFF69756E), fontWeight: FontWeight.w600)),
            if (liveAssignmentsEnabled) ...[
              const SizedBox(height: 18),
              const _AssignedStudentPulse(),
            ],
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(
                    child: _SummaryCard(
                        label: 'Q1 position',
                        value: '18%',
                        detail: 'Week 2 of 8',
                        icon: Icons.track_changes_rounded,
                        color: Color(0xFF4F5FA8))),
                SizedBox(width: 10),
                Expanded(
                    child: _SummaryCard(
                        label: 'Focus now',
                        value: '6',
                        detail: 'students',
                        icon: Icons.person_search_rounded,
                        color: Color(0xFFB06D21))),
                SizedBox(width: 10),
                Expanded(
                    child: _SummaryCard(
                        label: 'Approvals',
                        value: '3',
                        detail: 'pending',
                        icon: Icons.approval_rounded,
                        color: Color(0xFF744F8E))),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle(
                title: 'Quarter target position',
                subtitle: 'Where we are standing now'),
            const SizedBox(height: 12),
            ...metrics.map((metric) => _MetricCard(metric: metric)),
            const SizedBox(height: 22),
            const _SectionTitle(
                title: 'This week’s realistic milestones',
                subtitle: 'Where we should reach by next Monday'),
            const SizedBox(height: 12),
            const _Milestone(
                number: '1',
                title: '7 personal conversations',
                detail: 'Move suitable students toward four rounds.'),
            const _Milestone(
                number: '2',
                title: '8 book motivations',
                detail: 'Restart students who stopped mid-book.'),
            const _Milestone(
                number: '3',
                title: '375 meaningful minutes',
                detail: 'Physical meeting, video call or phone call.'),
            const _Milestone(
                number: '4',
                title: '2 RDUA leaders confirmed',
                detail: 'Sincerity and willingness remain the key judgment.'),
            const SizedBox(height: 22),
            const _SectionTitle(
                title: 'Students to focus on',
                subtitle: 'Reason and one clear next action'),
            const SizedBox(height: 12),
            ...focusStudents.map((student) => _FocusCard(student: student)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: const Color(0xFFF0EAF6),
                  borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.verified_user_outlined,
                        color: Color(0xFF744F8E)),
                    SizedBox(width: 9),
                    Text('Guide approvals',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4E345E)))
                  ]),
                  const SizedBox(height: 12),
                  const Text(
                      '• 2 expedition discounts\n• 1 student-reported exam-date change\n• 3 drafted book motivations',
                      style: TextStyle(
                          height: 1.65,
                          color: Color(0xFF5D4968),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 13),
                  const Text(
                      'Nothing is sent or applied until a guide approves it.',
                      style: TextStyle(
                          color: Color(0xFF744F8E),
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CompetitionPage())),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Open competition management'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF24372C))),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(
                color: Color(0xFF748078),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]);
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label,
      required this.value,
      required this.detail,
      required this.icon,
      required this.color});
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E8E2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 11),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF7B857F),
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFF26352C),
                  fontWeight: FontWeight.w900)),
          Text(detail,
              style: const TextStyle(fontSize: 10, color: Color(0xFF7B857F))),
        ]),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _QuarterMetric metric;
  @override
  Widget build(BuildContext context) {
    final progress = (metric.actual / metric.target).clamp(0, 1).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E8E2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(metric.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF2B3A31)))),
          Text('${metric.actual} / ${metric.target}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: Color(0xFF4F5FA8)))
        ]),
        const SizedBox(height: 11),
        LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFFE5E8E3),
            color: const Color(0xFF4F5FA8)),
        const SizedBox(height: 9),
        Text(metric.note,
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF737D77),
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Milestone extends StatelessWidget {
  const _Milestone(
      {required this.number, required this.title, required this.detail});
  final String number;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE4E8E2))),
        child: Row(children: [
          CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFF315F45),
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: Color(0xFF2B3A31))),
                const SizedBox(height: 3),
                Text(detail,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF747E78)))
              ])),
        ]),
      );
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.student});
  final _FocusStudent student;
  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentJourneyProfilePage(
                studentName: student.name,
                cohort: student.cohort,
              ),
            ),
          ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xFFE4E8E2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(student.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF26352C))),
                  Text(student.cohort,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF7A857E),
                          fontWeight: FontWeight.w700))
                ])),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFFEDEFFC),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('By ${student.due}',
                    style: const TextStyle(
                        color: Color(0xFF4F5FA8),
                        fontSize: 11,
                        fontWeight: FontWeight.w900)))
          ]),
          const SizedBox(height: 11),
          Text(student.reason,
              style: const TextStyle(
                  color: Color(0xFF626E67),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.arrow_forward_rounded,
                size: 17, color: Color(0xFF315F45)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(student.action,
                    style: const TextStyle(
                        color: Color(0xFF2E4638),
                        fontSize: 12,
                        fontWeight: FontWeight.w800)))
          ]),
        ]),
      ));
}

class _QuarterMetric {
  const _QuarterMetric(this.title, this.actual, this.target, this.note);
  final String title;
  final int actual;
  final int target;
  final String note;
}

class _FocusStudent {
  const _FocusStudent(
      this.name, this.cohort, this.reason, this.action, this.due);
  final String name;
  final String cohort;
  final String reason;
  final String action;
  final String due;
}

class _AssignedStudentPulse extends StatelessWidget {
  const _AssignedStudentPulse();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AssignedStudentSnapshot>>(
      future: const AssignedStudentRepository().load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _PulseMessage(
            icon: Icons.cloud_off_rounded,
            message:
                'Assigned-student data could not be loaded. Check the test identity and guide assignment.',
          );
        }
        final students = snapshot.data ?? const <AssignedStudentSnapshot>[];
        if (students.isEmpty) {
          return const _PulseMessage(
            icon: Icons.person_add_alt_1_rounded,
            message:
                'This guide has no active student assignments in the test database yet.',
          );
        }
        final recent = students
            .where((student) => (student.daysSinceEntry ?? 999) <= 1)
            .length;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4ED),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCDE2D3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.sync_rounded, color: Color(0xFF315F45)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${students.length} assigned · $recent recent submissions',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF294936),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...students.take(4).map(
                    (student) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: const Color(0xFF315F45),
                            child: Text(
                              '${student.chantingRounds ?? 0}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${student.fullName}${student.isSynthetic ? ' · TEST' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF294936),
                                  ),
                                ),
                                Text(
                                  student.focusReason,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF5F7567),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const Text(
                'Circle values are the latest reported chanting rounds. No message is sent from this view.',
                style: TextStyle(
                  color: Color(0xFF52705D),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulseMessage extends StatelessWidget {
  const _PulseMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E8E2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF69756E)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF69756E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}
