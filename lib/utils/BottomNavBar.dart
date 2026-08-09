import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_guide_app/Home/MainPage.dart';
import 'package:folk_guide_app/Home/WeeklyMilestoneDashboard.dart';
import 'package:folk_guide_app/Home/OperationsCenter.dart';
import 'package:folk_guide_app/utils/MalaLoading.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Pages/FolkGuideSelect.dart';
import '../Services/FolkIdentityService.dart';
import '../config/AppConfiguration.dart';
import 'ColorProvider.dart';

class CurvedNavBar extends StatefulWidget {
  final String Guidename;
  const CurvedNavBar(this.Guidename);
  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> {
  int currentIdx = 1; // Set default index to 1 for CalendarPage
  final List<String> titles = ['Weekly Plan', 'FOLK Boys', 'Operations'];
  late String adminName = widget.Guidename;
  bool isLoading = true; // Flag to indicate loading state
  late List<Widget> screens; // ✅ declare late

  @override
  void initState() {
    super.initState();
    // Initialize screens with placeholders first
    screens = [
      WeeklyMilestoneDashboard(guideName: adminName),
      DashboardScreen(
        selectedGuide: adminName,
      ),
      OperationsCenterPage(guideName: adminName)
    ];

    isLoading = false;
  }

  void _logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Confirm Logout"),
        content: Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Logout")),
        ],
      ),
    );

    if (confirm ?? false) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_guide');

      if (AppConfiguration.googleOnlyAuthEnabled) {
        await FolkIdentityService.signOut();
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => FolkGuideSelectionPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            titles[currentIdx],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 25,
              color: colorProvider.secondColor,
            ),
          ),
          backgroundColor: colorProvider.color,
          actions: [
            if (currentIdx == 1)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: "Logout",
                onPressed: _logout,
                color: colorProvider.secondColor,
              )
          ],
        ),
        body: isLoading
            ? CustomLoader() // Show loading indicator
            : screens[currentIdx], // Show the correct screen
        bottomNavigationBar: SafeArea(
          top: false,
          child: CurvedNavigationBar(
            items: const <Widget>[
              Icon(
                Icons.track_changes_rounded,
                size: 30,
                color: Colors.white,
              ),
              Icon(
                Icons.mark_unread_chat_alt_outlined,
                size: 30,
                color: Colors.white,
              ),
              Icon(
                Icons.dashboard_customize_outlined,
                size: 30,
                color: Colors.white,
              ),
            ],
            buttonBackgroundColor: colorProvider.thirdColor,
            backgroundColor: colorProvider.color,
            color: colorProvider.thirdColor,
            animationCurve: Curves.easeInOut,
            height: 68,
            animationDuration: const Duration(milliseconds: 250),
            index: currentIdx, // Set the initial selected index
            onTap: (index) {
              setState(() {
                currentIdx = index;
              });
            },
          ),
        ),
      );
    });
  }
}
