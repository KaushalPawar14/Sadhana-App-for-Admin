import 'package:flutter/material.dart';

import '../theme/GuideTokens.dart';
import 'GuideGhost.dart';

/// The ghost of the board: two column shells (a header bar and five 60 dp cards each)
/// in the same horizontal list, with the same padding and column width as the real
/// board, so the real columns appear exactly where the ghosts were.
class GuideBoardGhost extends StatelessWidget {
  const GuideBoardGhost({super.key, required this.columnWidth});

  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          GuideSpace.pagePadding, 4, GuideSpace.pagePadding - GuideBoardTokens.columnGap, 20),
      children: [
        for (var i = 0; i < 2; i++)
          Container(
            width: columnWidth,
            margin: const EdgeInsets.only(right: GuideBoardTokens.columnGap),
            child: Stack(
              children: [
                const Positioned.fill(child: GuideGhost(radius: GuideShape.columnRadius)),
                SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              GuideGhost(width: 3, height: 34, radius: 2),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GuideGhostBar(width: 120, height: 14),
                                    SizedBox(height: 6),
                                    GuideGhostBar(width: 80, height: 10),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8),
                              GuideGhost(width: 28, height: 22, radius: 11),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (var j = 0; j < 5; j++)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: GuideGhost(height: GuideBoardTokens.cardHeight, radius: 16),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
