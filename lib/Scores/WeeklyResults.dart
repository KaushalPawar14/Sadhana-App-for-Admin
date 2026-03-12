import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';
import '../utils/PercentageService.dart';

class WeeklyCompetitionScreen extends StatefulWidget {
  const WeeklyCompetitionScreen({super.key});

  @override
  State<WeeklyCompetitionScreen> createState() =>
      _WeeklyCompetitionScreenState();
}

class _WeeklyCompetitionScreenState extends State<WeeklyCompetitionScreen>
    with TickerProviderStateMixin {
  String? selectedUser;
  Map<String, Map<String, double>> userPercentageChanges = {};
  bool isLoadingPercentage = true;
  late AnimationController controller;
  late Animation<double> scaleAnimation;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    scaleAnimation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> loadUserPercentages(String username) async {
    setState(() {
      isLoadingPercentage = true;
    });

    final service = PercentageService();
    final result = await service.getWeeklyPercentageChange(username: username);

    setState(() {
      userPercentageChanges[username] = result;
      isLoadingPercentage = false;
    });
  }

  Widget buildAdminUserCard(Map<String, dynamic> user) {
    final colorProvider = Provider.of<ColorProvider>(context);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey,
            Colors.white70,
            Color(0xFFE6E6E6),
            Colors.grey,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(width: 0.8, color: colorProvider.secondColor),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔥 TOTAL SCORE HEADER
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Total Weekly Score",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  user['score'].toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            /// 📊 PERFORMANCE CHIPS
            Wrap(
              spacing: 15,
              runSpacing: 20,
              children: [
                infoChip("📖 SB Class", user['bhagavatam'], selectedUser ?? "",
                    "weekly.bhagavatam_class"),
                infoChip("🙏 Service", user['dailyService'], selectedUser ?? "",
                    "weekly.daily_service"),
                infoChip("🕉️ Chanting", user['chanting'], selectedUser ?? "",
                    "weekly.chanting_rounds"),
                infoChip("📚 Reading", user['bookReading'], selectedUser ?? "",
                    "weekly.book_reading"),
                infoChip("🎤 Lecture", user['extraLecture'], selectedUser ?? "",
                    "weekly.extra_lecture"),
                infoChip("📅 Days", user['days'], selectedUser ?? "",
                    "weekly.days_count"),
              ],
            ),

            const SizedBox(height: 26),

            /// 🔹 MULTIPLIERS
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  Text("🏛 Temple x ${user['templeMultiplier']}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text("📿 Japa x ${user['japaMultiplier']}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text("😴 Sleep x ${user['sleepMultiplier']}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget infoChip(
      String label, dynamic value, String userKey, String metricKey) {
    String display = (value ?? 0).toDouble().toStringAsFixed(2);
    double? percent = userPercentageChanges[userKey]?[metricKey];

    Color glowColor = percent == null
        ? Colors.transparent
        : percent > 0
        ? Colors.green.withOpacity(0.3)
        : percent < 0
        ? Colors.red.withOpacity(0.3)
        : Colors.transparent;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0, end: 1.0),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Colors.grey.shade100],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: glowColor,
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$label: $display",
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (percent ?? 0) > 0
                          ? Icons.arrow_upward
                          : (percent ?? 0) < 0
                              ? Icons.arrow_downward
                              : Icons.remove,
                      size: 12,
                      color: (percent ?? 0) > 0
                          ? Colors.green
                          : (percent ?? 0) < 0
                              ? Colors.red
                              : Colors.grey,
                    ),
                    const SizedBox(width: 2),
                    isLoadingPercentage
                        ? const SizedBox(
                            height: 12,
                            width: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            percent == null
                                ? "0%"
                                : "${percent > 0 ? "+" : ""}${percent.toStringAsFixed(1)}%",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: percent == null
                                  ? Colors.grey
                                  : percent > 0
                                      ? Colors.green
                                      : percent < 0
                                          ? Colors.red
                                          : Colors.grey,
                            ),
                          )
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  double formatDouble(dynamic value) {
    return double.parse((value ?? 0).toDouble().toStringAsFixed(2));
  }

  Widget buildAnimatedUserCard(Map<String, dynamic> user) {
    return ScaleTransition(
      scale: scaleAnimation,
      child: buildAdminUserCard(user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorProvider = Provider.of<ColorProvider>(context);

    return Scaffold(
      backgroundColor: colorProvider.color,
      appBar: AppBar(
        title: Text(
          "Weekly Reports",
          style: TextStyle(
              fontWeight: FontWeight.bold, color: colorProvider.secondColor),
        ),
        backgroundColor: colorProvider.color,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: colorProvider.secondColor,
          ),
          onPressed: () {
            // Perform any action when the icon is pressed, e.g., navigate back
            Navigator.pop(context);
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance.collection('competition').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No Data Available"));
          }

          if (selectedUser == null) {
            selectedUser = docs.first.id;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.forward(from: 0);
              loadUserPercentages(selectedUser!);
            });
          }

          return Column(
            children: [
              /// 🔵 TOP USER SELECTOR (Horizontal)
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final username = docs[index].id;
                    final isSelected = username == selectedUser;

                    return GestureDetector(
                      onTap: () async {
                        if (selectedUser == username) return;

                        setState(() => selectedUser = username);

                        controller.forward(from: 0);

                        await loadUserPercentages(username);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? Colors.blue : Colors.blue.shade200,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.4),
                                    blurRadius: 10,
                                  )
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            username,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? colorProvider.secondColor
                                  : colorProvider.color,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('competition')
                      .doc(selectedUser)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.data!.exists) {
                      return const Center(
                          child: Text("No weekly data available."));
                    }

                    final data = snapshot.data!.data();
                    if (data == null) {
                      return const Center(child: Text("Empty data"));
                    }

                    final userData = {
                      "score": formatDouble(data['weekly.total_score'] ?? 0)
                          .toDouble(),
                      "bhagavatam":
                          formatDouble(data['weekly.bhagavatam_class'] ?? 0)
                              .toDouble(),
                      "dailyService":
                          formatDouble(data['weekly.daily_service'] ?? 0)
                              .toDouble(),
                      "chanting":
                          formatDouble(data['weekly.chanting_rounds'] ?? 0)
                              .toDouble(),
                      "bookReading":
                          formatDouble(data['weekly.book_reading'] ?? 0)
                              .toDouble(),
                      "extraLecture":
                          formatDouble(data['weekly.extra_lecture'] ?? 0)
                              .toDouble(),
                      "templeMultiplier":
                          formatDouble(data['weekly.temple_multiplier'] ?? 0)
                              .toDouble(),
                      "japaMultiplier":
                          formatDouble(data['weekly.japa_multiplier'] ?? 0)
                              .toDouble(),
                      "sleepMultiplier":
                          formatDouble(data['weekly.sleeping_multiplier'] ?? 0)
                              .toDouble(),
                      "days": (data['weekly.days_count'] ?? 0).toInt(),
                    };

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: buildAnimatedUserCard(userData),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
