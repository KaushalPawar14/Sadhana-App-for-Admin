import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';
import '../Services/MissingReportNotification.dart';
import '../utils/ColorProvider.dart';
import 'AdminRegisterUserPage.dart';
import 'BookReadReport.dart';

class AdminControlPage extends StatefulWidget {
  const AdminControlPage({super.key});

  @override
  State<AdminControlPage> createState() => _AdminControlPageState();
}

class _AdminControlPageState extends State<AdminControlPage>
    with TickerProviderStateMixin {

  late AnimationController floatController;

  @override
  void initState() {
    super.initState();

    floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final colorProvider = Provider.of<ColorProvider>(context);

    return Scaffold(
      backgroundColor: colorProvider.color,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {

            double size =
            constraints.maxWidth > 600 && constraints.maxHeight > 700 ? 130 : 100;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 45),
                child: Column(
                  children: [

                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _actionBlob(
                          icon: Icons.group_add,
                          title: "Add Hostelers",
                          color: Colors.blue,
                          size: size,
                          onTap: () {
                            Navigator.push(
                                context,
                                PageRouteBuilder(
                                    pageBuilder: (_, __, ___) =>
                                        AdminRegisterUserPage(),
                                    transitionsBuilder:
                                        (_, animation, __, child) {
                                      return FadeTransition(
                                          opacity: animation, child: child);
                                    }));
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 0),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _actionBlob(
                          icon: Icons.notifications_active,
                          title: "Send Notification",
                          color: Colors.blue,
                          size: size,
                          onTap: () async{
                            await NotificationManager().sendReminder(
                                "Hare Krishna Prabhu !! 🙏🙏",
                                "Kindly fill up your Sadhana report 📝 for today."
                            );
                            showSnackbar(context, "Notifications sent successfully !!", Colors.green, Icons.circle_notifications_sharp);
                            print("Notifications sent!");
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 0),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _actionBlob(
                          icon: Icons.menu_book_rounded,
                          title: "Reading Status",
                          color: Colors.blue,
                          size: size,
                          onTap: () {
                            Navigator.push(
                                context,
                                PageRouteBuilder(
                                    pageBuilder: (_, __, ___) =>
                                        BookReadingScreen(),
                                    transitionsBuilder:
                                        (_, animation, __, child) {
                                      return FadeTransition(
                                          opacity: animation, child: child);
                                    }));
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 0),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _actionBlob(
                          icon: Icons.assignment_turned_in,
                          title: "Assign Tasks",
                          color: Colors.blue,
                          size: size,
                          onTap: () {
                            // uploadForAllUsers();
                            showSnackbar(context, "Will be available later", Colors.brown, Icons.assignment_late_rounded);
                          },
                        ),
                      ],
                    ),

                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _actionBlob({
    required IconData icon,
    required String title,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {

    final colorProvider = Provider.of<ColorProvider>(context);

    return AnimatedBuilder(
      animation: floatController,
      builder: (context, child) {

        double offset = sin(floatController.value * 2 * pi) * 6;

        return Transform.translate(
          offset: Offset(0, offset),
          child: GestureDetector(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Container(
                  height: size,
                  width: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        color,
                        Colors.blue.shade100,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: size * 0.35,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: colorProvider.secondColor
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

// final Map<String, List<String>> questionLevels = {
//   "level-1": [
//     "Who am I?",
//     "Does God exist?",
//     "GOD Vs. Demigods & Definition of GOD",
//     "Yugadharma for Kaliyuga",
//     "Laws of Karma",
//   ],
//
//   "level-2": [
//     "Importance of Vedic Literatures",
//     "3 modes of material Nature",
//     "Reincarnation",
//     "Material world Vs. Spiritual world",
//     "4 regulative Principles",
//   ],
//
//   "level-3": [
//     "Energies of Lord Krishna",
//     "Incarnations of Lord Krishna",
//     "Glories of devotional service",
//     "Purpose of Human form of Life",
//     "Importance of accepting a Spiritual Master",
//   ],
//
//   "level-4": [
//     "3 features of Absolute Truth",
//     "Deity Worship or Idol Worship",
//     "Why so many religions in different parts of the World",
//     "Glories of Visiting Lord's Dhams",
//     "Glories of Vaishnava association",
//   ],
//
//   "level-5": [
//     "Importance of ekadashi and observing fasting on acharyas appearance etc",
//     "Pranam Mantras of Deities",
//     "Vaishnava etiquettes",
//     "Different kinds of Liberation",
//     "Different kinds of mellows of relationship with the Lord",
//     "Glories of Preaching Krishna consciousness to others",
//   ]
// };
//
// Future<void> uploadForAllUsers() async {
//
//   final users = await FirebaseFirestore.instance.collection('users').get();
//
//   for (var user in users.docs) {
//     await uploadQuestions(user.id);
//   }
//
//   print("All users updated");
// }
//
// Future<void> uploadQuestions(String uid) async {
//
//   final ref = FirebaseFirestore.instance
//       .collection('users')
//       .doc(uid)
//       .collection('questions');
//
//   for (var level in questionLevels.entries) {
//
//     Map<String, dynamic> data = {};
//
//     for (int i = 0; i < level.value.length; i++) {
//       data['q${i + 1}'] = {
//         "question": level.value[i],
//         "completed": false,
//       };
//     }
//
//     await ref.doc(level.key).set(data);
//   }
// }