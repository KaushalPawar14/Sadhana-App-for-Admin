import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/StudentScope.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../utils/GuideDb.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideEntry.dart';

class BookReadingScreen extends StatefulWidget {
  const BookReadingScreen({super.key});

  @override
  State<BookReadingScreen> createState() => _CheckSadhanaScreenState();
}

class _CheckSadhanaScreenState extends State<BookReadingScreen> {

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: context.gText.body),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Legacy name-keyed `booksRead/{student}/{level}` data: HOD only (app and rules).
    if (!AdminProfileProvider.viewerIsHod) return const _HodOnlyScreen();
    final g = context.g;
    final t = context.gText;

    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: 'Books read'),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Scoped to the students this admin may see (HOD: everything).
              stream: StudentScope.current().historyStream('booksRead'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const GuideWait();
                }

                if (snapshot.hasError) {
                  return _message("Error: ${snapshot.error}");
                }

                if (!snapshot.hasData) return _message("No books found.");

                // Real student documents are keyed by student name. The newer
                // per-book progress documents use "{uid}_{level}_{bookKey}", so
                // any id containing an underscore is not a student.
                final books = snapshot.data!.docs
                    .where((doc) => !doc.id.contains('_'))
                    .toList();

                if (books.isEmpty) return _message("No books found.");

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 28),
                  itemCount: books.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final name = books[index].id;
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : "?";

                    return GuideEntry(
                      index: index,
                      child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GuideCard(
                        padding: EdgeInsets.zero,
                        clip: true,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentDetailScreen(student: name),
                              ),
                            );
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 64),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: g.chipBackground, shape: BoxShape.circle),
                                    child: Text(initial,
                                        style: t.bodyStrong
                                            .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.cardTitle),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: g.mutedText),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StudentDetailScreen extends StatelessWidget {
  final String student;

  StudentDetailScreen({required this.student});

  Stream<String?> _currentBookStream() {
    return GuideDb.instance
        .collection('booksRead')
        .doc(student)
        .snapshots()
        .map((doc) => doc.data()?['currentBook']);
  }

  Stream<Map<String, List<Map<String, dynamic>>>> _booksStream() async* {

    final levels = ['level-1', 'level-2', 'level-3'];

    while (true) {

      Map<String, List<Map<String, dynamic>>> booksByLevel = {};

      for (String level in levels) {

        final snapshot = await GuideDb.instance
            .collection('booksRead')
            .doc(student)
            .collection(level)
            .get();

        List<Map<String, dynamic>> books = snapshot.docs.map((doc) {

          final data = doc.data();

          return {
            "name": data["bookName"] ?? doc.id,
            "notes": data["madeNotes"] ?? false,
            "startDate": data["startDate"] ?? "",
          };

        }).toList();

        booksByLevel[level] = books;
      }

      yield booksByLevel;

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Legacy name-keyed `booksRead/{student}/{level}` data: HOD only (app and rules).
    if (!AdminProfileProvider.viewerIsHod) return const _HodOnlyScreen();
    final g = context.g;
    final t = context.gText;

    return GuideScaffold(
      body: Column(
        children: [
          GuideTopBar(title: student, titleMaxLines: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// CURRENT BOOK
                  StreamBuilder<String?>(
                    stream: _currentBookStream(),
                    builder: (context, snapshot) {

                      if (!snapshot.hasData) return const SizedBox();

                      return GuideHeroPanel(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.menu_book_outlined,
                                color: GuideColors.heroLabel, size: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Currently reading",
                                      style: t.small.copyWith(color: GuideColors.heroMuted)),
                                  const SizedBox(height: 4),
                                  Text(
                                    snapshot.data ?? "",
                                    style: t.cardTitle
                                        .copyWith(color: GuideColors.heroText, fontSize: 20),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 22),

                  /// BOOK LEVELS
                  StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
                    stream: _booksStream(),
                    builder: (context, snapshot) {

                      if (!snapshot.hasData) {
                        return GuideWait(snapshot: snapshot);
                      }

                      final booksByLevel = snapshot.data!;

                      return Column(
                        children: booksByLevel.entries.map((entry) {

                          final levelBooks = entry.value;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: GuideCard(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  GuideLabel(entry.key.toUpperCase()),

                                  const SizedBox(height: 12),

                                  ...levelBooks.map((book) {
                                    final notes = book["notes"] == true;
                                    return Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        color: g.chipBackground,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: g.brass.withValues(alpha: .14),
                                            ),
                                            child: Icon(Icons.menu_book_outlined,
                                                size: 18, color: g.brass),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(book["name"], style: t.cardTitle),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 16,
                                                  runSpacing: 4,
                                                  children: [
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.calendar_today_outlined,
                                                            size: 12, color: g.mutedText),
                                                        const SizedBox(width: 4),
                                                        Flexible(child: Text(book["startDate"], style: t.caption))],
                                                    ),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          notes
                                                              ? Icons.check_circle_outline
                                                              : Icons.cancel_outlined,
                                                          size: 14,
                                                          color: notes ? g.success : g.danger,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Flexible(child: Text(
                                                          notes ? "Notes made" : "No notes",
                                                          style: t.caption.copyWith(
                                                              color: notes ? g.success : g.danger),
                                                        ))],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                  }).toList()
                                ],
                              ),
                            ),
                          );

                        }).toList(),
                      );
                    },
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Shown instead of the legacy "Books Read" screens to anyone who is not a HOD
/// (the old name-keyed `booksRead/{student}/{level}` data is HOD-only, in the app
/// and in the security rules).
class _HodOnlyScreen extends StatelessWidget {
  const _HodOnlyScreen();

  @override
  Widget build(BuildContext context) {
    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: 'Books read'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This report is only available to the HOD.',
                  textAlign: TextAlign.center,
                  style: context.gText.body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
