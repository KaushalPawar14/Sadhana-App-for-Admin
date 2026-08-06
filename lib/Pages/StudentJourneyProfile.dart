import 'package:flutter/material.dart';

class StudentJourneyProfilePage extends StatelessWidget {
  const StudentJourneyProfilePage({
    super.key,
    required this.studentName,
    required this.cohort,
  });

  final String studentName;
  final String cohort;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F2),
      appBar: AppBar(
        title: const Text('Student journey'),
        backgroundColor: const Color(0xFFF5F6F2),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF294F3A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cohort,
                  style: const TextStyle(color: Color(0xFFD4E3D8)),
                ),
                const SizedBox(height: 15),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip('Q1 · active'),
                    _HeaderChip('4–7 rounds'),
                    _HeaderChip('Association due'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _Notice(),
          const SizedBox(height: 22),
          const _Title(
            'Private LIT assessment',
            'Evidence-based guide judgment; reassess after three meaningful interactions.',
          ),
          const SizedBox(height: 12),
          const _LitPanel(),
          const SizedBox(height: 22),
          const _Title(
            'ABCDE journey',
            'Keep each spiritual activity visible instead of hiding it in one score.',
          ),
          const SizedBox(height: 12),
          const _AbcdePanel(),
          const SizedBox(height: 22),
          const _Title(
            'What needs attention',
            'One clear, relationship-aware next step for the guide.',
          ),
          const SizedBox(height: 12),
          const _AttentionCard(),
          const SizedBox(height: 22),
          const _Title(
            'Recent mentor-approved summaries',
            'Raw dictation is discarded after the guide approves the concise summary.',
          ),
          const SizedBox(height: 12),
          const _InteractionCard(),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _openInteractionComposer(context),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Record an interaction summary'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF315F45),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      ),
    );
  }

  void _openInteractionComposer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Natural interaction note',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            const Text(
              'Speak or paste naturally. The system will propose only missing clarifications and a concise summary for your approval.',
              style: TextStyle(color: Color(0xFF68736C), height: 1.4),
            ),
            const SizedBox(height: 15),
            const TextField(
              maxLines: 7,
              decoration: InputDecoration(
                hintText: 'What happened in the interaction?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Prototype saved locally; no student data or message was sent.',
                      ),
                    ),
                  );
                },
                child: const Text('Create draft summary'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x26FFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1CE),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: Color(0xFF795218)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Representative test profile. Live values will come from approved guide inputs and observable activity.',
                style: TextStyle(
                  color: Color(0xFF795218),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF24372C),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF748078),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      );
}

class _LitPanel extends StatelessWidget {
  const _LitPanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: _panelDecoration,
        child: const Column(
          children: [
            _ScaleRow('L · Listens and follows', 4, Color(0xFF4D7D5B)),
            SizedBox(height: 14),
            _ScaleRow('I · Interest in philosophy', 5, Color(0xFFB27729)),
            SizedBox(height: 14),
            _ScaleRow('T · Time presently available', 2, Color(0xFF685390)),
            Divider(height: 28),
            Row(
              children: [
                Icon(Icons.insights_rounded, color: Color(0xFF315F45)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'High interest, limited time: give a small, consistent reading step and avoid overload.',
                    style: TextStyle(
                      color: Color(0xFF405148),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(
                '$value / 5',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: value / 5,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFFE6E9E4),
            color: color,
          ),
        ],
      );
}

class _AbcdePanel extends StatelessWidget {
  const _AbcdePanel();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration,
        child: const Column(
          children: [
            _ActivityRow('A', 'Association', '68 / 125 min · due', 0.54),
            _ActivityRow('B', 'Books', 'Paused after chapter 2', 0.32),
            _ActivityRow('C', 'Chanting', '4–7 round bracket', 0.58),
            _ActivityRow('D', 'Devotional service', 'One trial service', 0.25),
            _ActivityRow('E', 'Expedition', 'Ahmedabad · interested', 0.45),
          ],
        ),
      );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.letter, this.label, this.detail, this.progress);
  final String letter;
  final String label;
  final String detail;
  final double progress;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFE7F0E8),
              child: Text(
                letter,
                style: const TextStyle(
                  color: Color(0xFF315F45),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: Color(0xFF6D7871),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(6),
                    color: const Color(0xFFD68A2D),
                    backgroundColor: const Color(0xFFECEDE8),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5E7),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFF0D3A7)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restart his book journey naturally',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF5E421F),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Ask what stayed with him from Chapter 2. Then introduce one intriguing question from the next three chapters and offer a brief physical meeting.',
              style: TextStyle(color: Color(0xFF6A563D), height: 1.45),
            ),
            SizedBox(height: 11),
            Text(
              'Why this guidance: reading paused, interest remains high, and personal association is overdue.',
              style: TextStyle(
                color: Color(0xFF916224),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _InteractionCard extends StatelessWidget {
  const _InteractionCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _panelDecoration,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF4D7D5B), size: 19),
                SizedBox(width: 8),
                Text(
                  'Physical meeting · 24 minutes',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            SizedBox(height: 9),
            Text(
              'He appreciated the hearing session but is worried about managing labs. He agreed to read ten minutes after dinner on three days this week.',
              style: TextStyle(color: Color(0xFF5F6B64), height: 1.45),
            ),
            SizedBox(height: 9),
            Text(
              'Approved by Amal Harinam Das · 2 interactions since last LIT review',
              style: TextStyle(
                color: Color(0xFF7A857E),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

const _panelDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.all(Radius.circular(19)),
  border: Border.fromBorderSide(BorderSide(color: Color(0xFFE3E7E1))),
);
