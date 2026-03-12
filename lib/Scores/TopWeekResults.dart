import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';

class WeeklyFullLeaderboard extends StatefulWidget {
  const WeeklyFullLeaderboard({super.key});

  @override
  State<WeeklyFullLeaderboard> createState() => _WeeklyFullLeaderboardState();
}

class _WeeklyFullLeaderboardState extends State<WeeklyFullLeaderboard> {
  final firestore = FirebaseFirestore.instance;

  String rankEmoji(int index) {
    if (index == 0) return "🥇";
    if (index == 1) return "🥈";
    if (index == 2) return "🥉";
    return "⭐";
  }

  Widget buildRow(String label, dynamic value) {

    final colorProvider = Provider.of<ColorProvider>(context);
    final num number = (value ?? 0) as num;
    final formatted = number.toDouble().toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorProvider.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatted,
              style: TextStyle(
                  color: colorProvider.secondColor, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }

  Widget buildUserCard(Map<String, dynamic> user, int index) {
    final colorProvider = Provider.of<ColorProvider>(context);
    final score = (user['weekly.total_score'] ?? 0) as num;
    final formattedScore = score.toDouble().toStringAsFixed(2);

    Color rankColor;

    if (index == 0) {
      rankColor = Colors.amber;
    } else if (index == 1) {
      rankColor = Colors.grey;
    } else if (index == 2) {
      rankColor = Colors.orange;
    } else {
      rankColor = Colors.blueGrey;
    }

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.blue.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 18,
          ),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: rankColor,
            child: Text(
              "${index + 1}",
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            user['username'] ?? "Unknown",
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: colorProvider.color),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: rankColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$formattedScore pts",
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          children: [
            Divider(color: colorProvider.color),
            buildRow("📖  Bhagavatam Class", user['weekly.bhagavatam_class']),
            buildRow("📚  Book Reading", user['weekly.book_reading']),
            buildRow("🧘  Chanting Rounds", user['weekly.chanting_rounds']),
            buildRow("🛕  Daily Service", user['weekly.daily_service']),
            buildRow("🎧  Extra Lecture", user['weekly.extra_lecture']),
            buildRow("📿  Japa Multiplier", user['weekly.japa_multiplier']),
            buildRow("🏛  Temple Multiplier", user['weekly.temple_multiplier']),
            buildRow(
                "🌙  Sleeping Multiplier", user['weekly.sleeping_multiplier']),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          title: Text("Weekly Ranking",style: TextStyle(color: colorProvider.secondColor, fontWeight: FontWeight.bold),),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
            onPressed: () => Navigator.pop(context),
          ),
          backgroundColor: colorProvider.color,
        ),
          body: StreamBuilder<DocumentSnapshot>(
            stream: firestore
                .collection('competition-results')
                .doc('weekly_meta')
                .snapshots(),
            builder: (context, metaSnapshot) {

              if (!metaSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final weekId = metaSnapshot.data!.get('last_week_finalized');

              if (weekId == null) {
                return const Center(
                  child: Text("No Results Found", style: TextStyle(color: Colors.white)),
                );
              }

              return StreamBuilder<DocumentSnapshot>(
                stream: firestore
                    .collection('competition-results')
                    .doc('weekly-participants')
                    .collection('weeks')
                    .doc(weekId)
                    .snapshots(),
                builder: (context, weekSnapshot) {

                  if (!weekSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final data =
                  weekSnapshot.data!.data() as Map<String, dynamic>?;

                  if (data == null) {
                    return const Center(
                      child: Text("No Results Found",
                          style: TextStyle(color: Colors.white)),
                    );
                  }

                  final List participantsRaw = data['participants'] ?? [];

                  final users = participantsRaw
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();

                  /// SORT BY SCORE
                  users.sort((a, b) =>
                      ((b['weekly.total_score'] ?? 0) as num)
                          .compareTo((a['weekly.total_score'] ?? 0) as num));

                  if (users.isEmpty) {
                    return const Center(
                      child: Text("No Results Found",
                          style: TextStyle(color: Colors.white)),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return buildUserCard(user, index);
                      },
                    ),
                  );
                },
              );
            },
          )
      );
    });
  }
}
