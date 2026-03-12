import 'package:flutter/material.dart';

class DateRangeProvider with ChangeNotifier {
  DateTimeRange _dateRange;

  DateRangeProvider()
      : _dateRange = DateTimeRange(
    start: DateTime.now().subtract(Duration(days: 30)),
    end: DateTime.now(),
  );

  DateTimeRange get dateRange => _dateRange;

  void setDateRange(DateTimeRange newRange) {
    _dateRange = newRange;
    notifyListeners();
  }
}
