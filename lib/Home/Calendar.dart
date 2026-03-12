import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ColorProvider.dart';

class CalendarPage extends StatefulWidget {
  final String username;
  final String role;

  CalendarPage({required this.username, required this.role});

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<String, dynamic>? _selectedDayData;
  bool _loadingDayData = false;
  bool _datePressed = false;

  String get collectionName =>
      widget.role == 'Stay at Hostel' ? 'hostel-sadhana' : 'sadhana-reports';

  Stream<Set<String>> _availableDatesStream() {
    return FirebaseFirestore.instance
        .collection(collectionName)
        .doc(widget.username)
        .collection('dates')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  Color _getDayColor(DateTime day, Set<String> availableDates) {
    String formattedDate = _formatDate(day);
    if (_selectedDay != null && isSameDay(day, _selectedDay)) return Colors.blue.shade400;
    if (availableDates.contains(formattedDate)) return Colors.green.shade600;
    return Colors.red.shade600;
  }

  Widget _dayCellWithColor(DateTime day, Color color, double size) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      width: size,
      height: size,
      margin: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  Future<void> _fetchSelectedDayData(DateTime selectedDay) async {
    setState(() {
      _loadingDayData = true;
      _selectedDayData = null;
      _datePressed = true;
    });

    try {
      String formattedDate = _formatDate(selectedDay);
      var doc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.username)
          .collection('dates')
          .doc(formattedDate)
          .get();

      setState(() {
        _selectedDayData = doc.exists ? doc.data() : {};
        _loadingDayData = false;
      });
    } catch (e) {
      print('Error fetching day data: $e');
      setState(() {
        _selectedDayData = {};
        _loadingDayData = false;
      });
    }
  }

  Widget _infoRow(String label, String value, Color color, [double? progress]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, color: Colors.black87)),
          if (progress != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: Duration(milliseconds: 800),
              builder: (context, valueAnim, child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: valueAnim,
                    color: color,
                    backgroundColor: Colors.grey.shade300,
                    minHeight: 8,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _selectedDayInfo() {
    if (!_datePressed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Select a date to see Sadhana 📖',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loadingDayData) return Center(child: CircularProgressIndicator());

    if (_selectedDayData == null || _selectedDayData!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No data found for this date ❌',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
      );
    }

    Map<String, dynamic> data = _selectedDayData!;
    List<Widget> rows = [];

    void add(String label, String value, Color color, [double? progress]) {
      rows.add(_infoRow(label, value, color, progress));
    }

    if (data.containsKey('chantRounds'))
      add('Chanting Rounds', '${data['chantRounds']} 📿', Colors.purple.shade700);
    if (data.containsKey('bookReading'))
      add('Book Reading', '${data['bookReading']} 📖', Colors.orange.shade700);
    if (data.containsKey('classHearing')) {
      double progress = data['classHearing'] == 2
          ? 1.0
          : data['classHearing'] == 1
          ? 0.5
          : 0.0;
      String val = data['classHearing'] == 2
          ? "Fully ✅"
          : data['classHearing'] == 1
          ? "Partial ⚠️"
          : "Missed ❌";
      add('Class Hearing', val, Colors.teal.shade700, progress);
    }
    if (data.containsKey('dailyServices')) {
      double progress = data['dailyServices'] == 2
          ? 1.0
          : data['dailyServices'] == 1
          ? 0.5
          : 0.0;
      String val = data['dailyServices'] == 2
          ? "Fully ✅"
          : data['dailyServices'] == 1
          ? "Partial ⚠️"
          : "Missed ❌";
      add('Daily Services', val, Colors.red.shade700, progress);
    }
    if (data.containsKey('templeEntry')) {
      add('Temple Entry', '${data['templeEntry']} ⛪', Colors.blueGrey.shade700);
    }
    if (data.containsKey('finishTiming')) {
      add('Finish Timing', '${data['finishTiming']} ⏰', Colors.green.shade700);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                blurRadius: 12,
                offset: Offset(0, 6))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final daySize = screenWidth * 0.11;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.username,
                style: TextStyle(color: colorProvider.secondColor)),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                // StreamBuilder for fast real-time date loading
                StreamBuilder<Set<String>>(
                  stream: _availableDatesStream(),
                  builder: (context, snapshot) {
                    final availableDates = snapshot.data ?? {};
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: TableCalendar(
                        firstDay: DateTime(DateTime.now().year, DateTime.now().month - 1, 1),
                        lastDay: DateTime.now(),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) =>
                        _selectedDay != null && isSameDay(day, _selectedDay),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });
                          _fetchSelectedDayData(selectedDay);
                        },
                        headerStyle: HeaderStyle(
                          titleCentered: true,
                          formatButtonVisible: false,
                          leftChevronIcon: Icon(Icons.chevron_left, color: colorProvider.secondColor),
                          rightChevronIcon: Icon(Icons.chevron_right, color: colorProvider.secondColor),
                          titleTextStyle: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colorProvider.secondColor),
                          headerPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                              color: colorProvider.secondColor,
                              fontWeight: FontWeight.w500),
                          weekendStyle: TextStyle(
                              color: colorProvider.secondColor,
                              fontWeight: FontWeight.w500),
                        ),
                        calendarStyle: CalendarStyle(
                          isTodayHighlighted: false,
                          cellMargin: EdgeInsets.zero,
                        ),
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (context, day, focusedDay) =>
                              _dayCellWithColor(day, _getDayColor(day, availableDates), daySize),
                          todayBuilder: (context, day, focusedDay) =>
                              _dayCellWithColor(day, _getDayColor(day, availableDates), daySize),
                          selectedBuilder: (context, day, focusedDay) =>
                              _dayCellWithColor(day, _getDayColor(day, availableDates), daySize),
                        ),
                      ),
                    );
                  },
                ),
                Divider(thickness: 1.5, color: Colors.grey.shade300),
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _selectedDayInfo(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}