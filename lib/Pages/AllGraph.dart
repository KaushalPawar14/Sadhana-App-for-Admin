import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/ColorProvider.dart';

class AllGraph extends StatefulWidget {
  final String username, role;
  const AllGraph({super.key, required this.username, required this.role});

  @override
  State<AllGraph> createState() => _ChantingGraphState();
}

class _ChantingGraphState extends State<AllGraph> {
  bool loading = true;
  List<bool> chantingAutoZero = [];
  List<int> chantingRounds = [];
  List<int> bookReadingData = [];
  List<int> templeEntryData = [];
  List<int> finishTimingData = [];
  Map<String, int> classHearingCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};
  Map<String, int> dailyServicesCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};

  DateTimeRange? selectedRange;

  DateTime get firstAllowedDate {
    final now = DateTime.now();

    // First day of previous month
    final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);

    return firstDayLastMonth;
  }

  DateTime get lastAllowedDate => DateTime.now();

  @override
  void initState() {
    super.initState();
    fetchChantingData();
    fetchTempleEntryData();
    fetchPieChartData();
  }

  Future<void> pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowedDate,
      lastDate: lastAllowedDate,
      initialDateRange: selectedRange ??
          DateTimeRange(
            start: firstAllowedDate,
            end: lastAllowedDate,
          ),
    );

    if (picked != null) {
      setState(() {
        selectedRange = picked;
      });

      // Reload all charts
      fetchChantingData();
      fetchTempleEntryData();
      fetchPieChartData();
    }
  }

  String getCollectionName() {
    return widget.role == 'Stay at Hostel' ? 'hostel-sadhana' : 'sadhana-reports';
  }

  Future<void> fetchPieChartData() async {
    final datesCollection = FirebaseFirestore.instance
        .collection(getCollectionName())
        .doc(widget.username)
        .collection('dates');

    final querySnapshot = await datesCollection.get();

    // Reset counts
    classHearingCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};
    dailyServicesCount = {'Fully': 0, 'Partial': 0, 'Missed': 0};

    for (final doc in querySnapshot.docs) {
      final data = doc.data();

      // 🔹 classHearing
      if (data.containsKey('classHearing')) {
        final val = data['classHearing'] as int;
        if (val == 2) classHearingCount['Fully'] = classHearingCount['Fully']! + 1;
        else if (val == 1) classHearingCount['Partial'] = classHearingCount['Partial']! + 1;
        else classHearingCount['Missed'] = classHearingCount['Missed']! + 1;
      }

      // 🔹 dailyServices
      if (data.containsKey('dailyServices')) {
        final val = data['dailyServices'] as int;
        if (val == 2) dailyServicesCount['Fully'] = dailyServicesCount['Fully']! + 1;
        else if (val == 1) dailyServicesCount['Partial'] = dailyServicesCount['Partial']! + 1;
        else dailyServicesCount['Missed'] = dailyServicesCount['Missed']! + 1;
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> fetchTempleEntryData() async {
    final startDate = selectedRange?.start ?? firstAllowedDate;
    final endDate = selectedRange?.end ?? lastAllowedDate;
    final dateFormat = DateFormat('dd-MM-yyyy');

    try {
      final datesCollection = FirebaseFirestore.instance
          .collection(getCollectionName())
          .doc(widget.username)
          .collection('dates');

      final querySnapshot = await datesCollection.get();

      Map<String, String> templeMap = {};
      Map<String, String> finishMap = {};

      for (final doc in querySnapshot.docs) {
        final dateString = doc.id;
        final data = doc.data();

        if (data.containsKey('templeEntry')) {
          templeMap[dateString] = data['templeEntry'] as String;
        }

        if (data.containsKey('finishTiming')) {
          finishMap[dateString] = data['finishTiming'] as String;
        }
      }

      List<int> templeList = [];
      List<int> finishList = [];

      for (DateTime day = startDate;
      !day.isAfter(endDate);
      day = day.add(const Duration(days: 1))) {
        final dayKey = dateFormat.format(day);

        if (templeMap.containsKey(dayKey)) {
          final timeStr = templeMap[dayKey]!; // "HH:mm"
          final parts = timeStr.split(":");
          if (parts.length == 2) {
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            final totalMinutes = hour * 60 + minute;
            templeList.add(totalMinutes);
          }
        }

        if (finishMap.containsKey(dayKey)) {
          final timeStr = finishMap[dayKey]!; // "HH:mm"
          final parts = timeStr.split(":");
          if (parts.length == 2) {
            final hour = int.tryParse(parts[0]) ?? 0;
            final minute = int.tryParse(parts[1]) ?? 0;
            final totalMinutes = hour * 60 + minute;
            finishList.add(totalMinutes);
          }
        }
      }

      if (mounted) {
        setState(() {
          templeEntryData = templeList;
          finishTimingData = finishList;
        });
      }
    } catch (e) {
      print("Error fetching templeEntry/finishTiming data: $e");
      if (mounted) {
        setState(() {
          templeEntryData = [];
          finishTimingData = [];
        });
      }
    }
  }

  Future<void> fetchChantingData() async {
    setState(() {
      loading = true;
    });

    final startDate = selectedRange?.start ?? firstAllowedDate;
    final endDate = selectedRange?.end ?? lastAllowedDate;
    final dateFormat = DateFormat('dd-MM-yyyy');

    try {
      final datesCollection = FirebaseFirestore.instance
          .collection(getCollectionName())
          .doc(widget.username)
          .collection('dates');

      final querySnapshot = await datesCollection.get();

      Map<String, int> roundsMap = {};
      Map<String, int> readingMap = {};

      for (final doc in querySnapshot.docs) {
        final dateString = doc.id;
        final data = doc.data();

        if (data.containsKey('chantRounds')) {
          roundsMap[dateString] = data['chantRounds'] as int;
        }

        if (data.containsKey('bookReading')) {
          readingMap[dateString] = data['bookReading'] as int;
        }
      }

      List<int> roundsList = [];
      List<int> readingList = [];
      List<bool> autoZeroFlags = [];

      for (DateTime day = startDate;
      !day.isAfter(endDate);
      day = day.add(const Duration(days: 1))) {
        final dayKey = dateFormat.format(day);

        // 🔹 Chanting data
        if (roundsMap.containsKey(dayKey)) {
          roundsList.add(roundsMap[dayKey]!);
          autoZeroFlags.add(false); // real entry
        } else {
          roundsList.add(0);
          autoZeroFlags.add(true); // auto-filled zero
        }

        // 🔹 Reading data (zero-filled, but no red marking needed)
        readingList.add(readingMap[dayKey] ?? 0);
      }

      if (mounted) {
        setState(() {
          chantingRounds = roundsList;
          chantingAutoZero = autoZeroFlags;
          bookReadingData = readingList;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          chantingRounds = [];
          chantingAutoZero = [];
          bookReadingData = [];
          loading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          title: Text(
            widget.username,
            style: TextStyle(color: colorProvider.secondColor),
          ),
          backgroundColor: colorProvider.color,
          iconTheme: IconThemeData(
            color: colorProvider.secondColor,
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: InkWell(
                    onTap: pickDateRange,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: colorProvider.secondColor,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.date_range, color: colorProvider.secondColor),
                          const SizedBox(width: 10),
                          Text(
                            selectedRange == null
                                ? "Select Date Range"
                                : "${DateFormat('dd MMM').format(selectedRange!.start)} - ${DateFormat('dd MMM').format(selectedRange!.end)}",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorProvider.secondColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Chanting 📿',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorProvider.secondColor),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                  const EdgeInsets.only(right: 16, top: 16, bottom: 5),
                  decoration: BoxDecoration(
                    color: colorProvider
                        .color, // Or use colorProvider.color for background
                    border: Border.all(
                        color: colorProvider.secondColor,
                        width: 2), // Border style
                    borderRadius:
                    BorderRadius.circular(12), // Optional: rounded corners
                  ),
                  height: 320,
                  width: 320,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(children: [
                    Expanded(child: MyLineChart(
                      chantingRounds: chantingRounds,
                      autoZeroFlags: chantingAutoZero,
                    ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Total: ${chantingRounds.fold(0, (a, b) => a + b)} rounds',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colorProvider.secondColor,
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 30), // 🔹 Spacer between charts

                // 🔸 Reading Chart
                Center(
                  child: Text(
                    'Reading 📖',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorProvider.secondColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                  const EdgeInsets.only(right: 16, top: 16, bottom: 5),
                  decoration: BoxDecoration(
                    color: colorProvider.color,
                    border:
                    Border.all(color: colorProvider.secondColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  height: 320,
                  width: 320,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                    children: [
                      Expanded(
                        child: MyLineChart(chantingRounds: bookReadingData, autoZeroFlags: chantingAutoZero,),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        bookReadingData.isEmpty
                            ? 'No Data'
                            : 'Average: ${(bookReadingData.reduce((a, b) => a + b) / bookReadingData.length).toStringAsFixed(1)} mins',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: colorProvider.secondColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Temple Entry ⛪',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorProvider.secondColor,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(
                      right: 16, top: 16, left: 16, bottom: 5),
                  decoration: BoxDecoration(
                    color: colorProvider.color,
                    border:
                    Border.all(color: colorProvider.secondColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  height: 320,
                  width: 320,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : TempleEntryChart(data: templeEntryData),
                ),
                const SizedBox(
                  height: 30,
                ),
                Text(
                  'Chanting Finish Timing ⏰',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorProvider.secondColor,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(
                      right: 16, top: 16, left: 16, bottom: 5),
                  decoration: BoxDecoration(
                    color: colorProvider.color,
                    border:
                    Border.all(color: colorProvider.secondColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  height: 320,
                  width: 320,
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : FinishTimingChart(data: finishTimingData),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Divider(
                    color: colorProvider.secondColor.withOpacity(0.5),
                    thickness: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                MyPieChart(data: classHearingCount, title: "Class Hearing 🎧"),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Divider(
                    color: colorProvider.secondColor.withOpacity(0.5),
                    thickness: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                MyPieChart(data: dailyServicesCount, title: "Daily Services 🛐"),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Divider(
                    color: colorProvider.secondColor.withOpacity(0.5),
                    thickness: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class MyPieChart extends StatelessWidget {
  final Map<String, int> data;
  final String title;

  const MyPieChart({super.key, required this.data, required this.title});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text("No data"));

    final sections = data.entries.map((e) {
      Color color;
      if (e.key == 'Fully') color = Colors.green;
      else if (e.key == 'Partial') color = Colors.yellow;
      else color = Colors.red;

      final percent = (e.value / total * 100);
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${percent.toStringAsFixed(1)}%',
        radius: 75,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      );
    }).toList();
    return Consumer<ColorProvider>(
        builder: (context, colorProvider, child) {
          return Column(
            children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorProvider.secondColor)),
              const SizedBox(height: 10),
              SizedBox(
                height: 250,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    sectionsSpace: 2,
                    centerSpaceRadius: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  LegendItem(color: Colors.green, text: "Fully"),
                  LegendItem(color: Colors.yellow, text: "Partial"),
                  LegendItem(color: Colors.red, text: "Missed"),
                ],
              ),
            ],
          );});
  }
}

class FinishTimingChart extends StatelessWidget {
  final List<int> data;
  const FinishTimingChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final barGroups = List.generate(data.length, (index) {
      // Cap bars at max 10:00 PM (1320 minutes)
      final cappedValue = data[index] > 1320 ? 1320 : data[index];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: cappedValue.toDouble(),
            gradient: _barGradient,
          ),
        ],
      );
    });

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              titlesData: FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                    y: 780, color: Colors.green, strokeWidth: 2), // 1:00 PM
                HorizontalLine(
                    y: 960, color: Colors.yellow, strokeWidth: 2), // 4:00 PM
                HorizontalLine(
                    y: 1320, color: Colors.red, strokeWidth: 2), // 10:00 PM
              ]),
              alignment: BarChartAlignment.spaceAround,
              maxY: 1320, // ✅ Cap Y axis at 10:00 PM
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ✅ Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            LegendItem(color: Colors.green, text: "1:00 PM"),
            LegendItem(color: Colors.yellow, text: "4:00 PM"),
            LegendItem(color: Colors.red, text: "10:00 PM"),
          ],
        )
      ],
    );
  }
}

class TempleEntryChart extends StatelessWidget {
  final List<int> data;
  const TempleEntryChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final barGroups = List.generate(data.length, (index) {
      // Cap each bar at 12:00 pm (720 mins)
      final cappedValue = data[index] > 600 ? 600 : data[index];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: cappedValue.toDouble(),
            gradient: _barGradient,
          ),
        ],
      );
    });

    // Always cap chart’s Y-axis at 12:00 pm (720 minutes)
    const double maxY = 600;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              titlesData: FlTitlesData(show: false), // Hide titles
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                    y: 330, color: Colors.green, strokeWidth: 2), // 5:30
                HorizontalLine(
                    y: 390, color: Colors.yellow, strokeWidth: 2), // 6:30
                HorizontalLine(
                    y: 450, color: Colors.red, strokeWidth: 2), // 7:30
              ]),
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Legend Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            LegendItem(
              color: Colors.green,
              text: "5:30 AM",
            ),
            LegendItem(color: Colors.yellow, text: "6:30 AM"),
            LegendItem(color: Colors.red, text: "7:30 AM"),
          ],
        )
      ],
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const LegendItem({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Row(
        children: [
          Container(
            width: 14,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorProvider.secondColor),
          ),
        ],
      );
    });
  }
}

class MyLineChart extends StatelessWidget {
  final List<int> chantingRounds;
  final List<bool> autoZeroFlags;

  const MyLineChart({
    super.key,
    required this.chantingRounds,
    required this.autoZeroFlags,
  });

  @override
  Widget build(BuildContext context) {
    if (chantingRounds.isEmpty) {
      return const Center(child: Text("No data"));
    }

    final spots = List.generate(
      chantingRounds.length,
          (index) => FlSpot(index.toDouble(), chantingRounds[index].toDouble()),
    );

    final minValue = chantingRounds.reduce((a, b) => a < b ? a : b).toDouble();
    final maxValue = chantingRounds.reduce((a, b) => a > b ? a : b).toDouble();

    final maxY = maxValue + (maxValue * 0.2);
    final minY = minValue - (minValue * 0.1);
    final finalMinY = minY < 0 ? 0 : minY;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return LineChart(
          LineChartData(
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      meta: meta,
                      space: 5,
                      child: Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
              rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: chantingRounds.length.toDouble() - 1,
            minY: 0,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.blueAccent,
                barWidth: 3,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.withOpacity(0.3),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    final isAutoZero =
                        index < autoZeroFlags.length && autoZeroFlags[index];

                    return FlDotCirclePainter(
                      radius: 4,
                      color:
                      isAutoZero ? Colors.red : Colors.blueAccent,
                      strokeWidth: 0,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

BarTouchData get barTouchData => BarTouchData(
  enabled: false,
  touchTooltipData: BarTouchTooltipData(
      tooltipPadding: EdgeInsets.zero,
      tooltipMargin: 8,
      getTooltipItem: (
          BarChartGroupData group,
          int groupIndex,
          BarChartRodData rod,
          int rodIndex,
          ) {
        return BarTooltipItem(
            rod.toY.toString(),
            const TextStyle(
                color: Colors.cyan, fontWeight: FontWeight.bold));
      }),
);

FlTitlesData get titlesData => FlTitlesData(
  show: true,
  bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: false,
        reservedSize: 30,
        // getTitlesWidget: getTitles,
      )),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  topTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
  rightTitles: AxisTitles(
    sideTitles: SideTitles(showTitles: false),
  ),
);

FlBorderData get borderData => FlBorderData(show: false);

LinearGradient get _barGradient => LinearGradient(
  colors: [
    Colors.lightBlueAccent,
    Colors.blueAccent,
  ],
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
);

