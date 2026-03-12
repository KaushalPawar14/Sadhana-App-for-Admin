import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Home/Dashboard.dart';
import 'package:folk_guide_app/Pages/BoysProfile.dart';
import 'package:folk_guide_app/Pages/FolkGuideSelect.dart';
import 'package:folk_guide_app/Services/UpdateFCM.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';

class DashboardScreen extends StatefulWidget {
  final String? selectedGuide;
  DashboardScreen({this.selectedGuide});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  String? selectedGuide;
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTokenForGuide();
      _fetchSavedGuide();
    });
  }

  Future<void> _fetchSavedGuide() async {
    String? guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (mounted) setState(() => selectedGuide = guide);
  }

  Future<void> _updateTokenForGuide() async {
    String? guide =
        widget.selectedGuide ?? await UpdateTokenService().getSavedGuide();
    if (guide == null) {
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => FolkGuideSelectionPage()));
      }
      return;
    }

    try {
      await UpdateTokenService().saveSelectedGuide(guide);
      String? fcmToken = await UpdateTokenService().getFCMToken();
      if (fcmToken == null) return;

      await FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(guide)
          .set({'fcmToken': fcmToken}, SetOptions(merge: true));
    } catch (e) {
      print("Failed to update FCM token: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: AnimatedOpacity(
          duration: const Duration(milliseconds: 600),
          opacity: _opacity,
          curve: Curves.easeIn,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: width * 0.04, vertical: height * 0.02),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: height * 0.01),
                  if (selectedGuide != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Folk Guide: $selectedGuide",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              color:
                              colorProvider.secondColor.withOpacity(0.8)),
                        ),
                        IconButton(
                            onPressed: () {
                              Provider.of<ColorProvider>(context, listen: false)
                                  .toggleColor();
                            },
                            icon: Icon(Icons.dark_mode,
                                color: colorProvider.secondColor, size: 28)),
                      ],
                    ),
                  SizedBox(height: height * 0.04),
                  Expanded(
                    child: ListView(
                      children: [
                        Center(
                          child: SizedBox(
                            width: 200,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DashboardTile(
                                icon: Lottie.asset(
                                  'assets/emoji/sadhana.json',
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.contain,
                                ),
                                title: "All Boys\nSadhana",
                                gradientColors: [
                                  Colors.blue.shade700,
                                  Colors.blue.shade300
                                ],
                                onTap: () => Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => Dashboard(),
                                    transitionsBuilder:
                                        (_, animation, __, child) =>
                                        FadeTransition(opacity: animation, child: child),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Center(
                          child: SizedBox(
                            width: 200,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DashboardTile(
                                icon: Lottie.asset(
                                  'assets/emoji/boy.json',
                                  width: 65,
                                  height: 65,
                                ),
                                title: "Boys\nProfile",
                                gradientColors: [
                                  Colors.lightBlue.shade700,
                                  Colors.lightBlue.shade300
                                ],
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context)=>BoysProfilePage()));
                                },
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class DashboardTile extends StatefulWidget {
  final String title;
  final Widget icon;
  final VoidCallback? onTap;
  final List<Color> gradientColors;

  const DashboardTile({
    required this.title,
    required this.icon,
    required this.gradientColors,
    this.onTap,
  });

  @override
  _DashboardTileState createState() => _DashboardTileState();
}

class _DashboardTileState extends State<DashboardTile> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) => setState(() => isPressed = false),
      onTapCancel: () => setState(() => isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: isPressed ? 6 : 14,
              offset: Offset(0, isPressed ? 3 : 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 45,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.6),
                      Colors.white.withOpacity(0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.icon,
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
