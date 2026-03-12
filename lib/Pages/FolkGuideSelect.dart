import 'package:flutter/material.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:provider/provider.dart';
import '../Home/MainPage.dart';
import 'package:sizer/sizer.dart';

import '../utils/ColorProvider.dart';

class FolkGuideSelectionPage extends StatelessWidget {
  final List<String> folkGuides = ["SBSD", "MMGD"];

  FolkGuideSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Fetch theme colors (these come automatically from your ColorProvider setup)
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
    return Scaffold(
      backgroundColor: colorProvider.color,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          "Select Your Folk Guide",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18.sp,
            color: colorProvider.secondColor,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
        child: ListView.builder(
          itemCount: folkGuides.length,
          itemBuilder: (context, index) {
            String guide = folkGuides[index];
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              margin: EdgeInsets.only(bottom: 2.h),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.blue.shade200, // pastel yellow tone
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 500),
                      pageBuilder: (_, __, ___) =>
                          CurvedNavBar(guide),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        const begin = Offset(0.1, 1.0);
                        const end = Offset.zero;
                        var curve = Curves.easeInOut;
                        var tween =
                        Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                        return SlideTransition(
                          position: animation.drive(tween),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 2.5.h, horizontal: 5.w),
                  child: Row(
                    children: [
                      Container(
                        height: 8.w,
                        width: 8.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.orange.withOpacity(0.4)
                              : Colors.orangeAccent.withOpacity(0.6),
                        ),
                        child: const Icon(Icons.bookmark_rounded,
                            color: Colors.white, size: 20),
                      ),
                      SizedBox(width: 5.w),
                      Expanded(
                        child: Text(
                          guide,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onBackground,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
    );}
}
