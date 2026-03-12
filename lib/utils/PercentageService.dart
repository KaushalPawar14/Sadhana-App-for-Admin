import 'package:cloud_firestore/cloud_firestore.dart';

class PercentageService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Main function
  Future<Map<String, double>> getWeeklyPercentageChange({
    required String username,
  }) async {
    // ---- STEP 1: Get last finalized week ----
    final metaDoc = await firestore
        .collection('competition-results')
        .doc('weekly_meta')
        .get();

    final lastWeekId = metaDoc.data()?['last_week_finalized'];

    if (lastWeekId == null) {
      return {};
    }

    // ---- STEP 2: Get previous week data ----
    final weekDoc = await firestore
        .collection('competition-results')
        .doc('weekly-participants')
        .collection('weeks')
        .doc(lastWeekId)
        .get();

    List participants = weekDoc.data()?['participants'] ?? [];

    Map<String, dynamic>? oldUser;

    for (var p in participants) {
      if (p['username'] == username) {
        oldUser = p;
        break;
      }
    }

    if (oldUser == null) {
      return {};
    }

    // ---- STEP 3: Normalize OLD data ----
    Map<String, double> oldNormalized = {};

    double oldDays =
    (oldUser['weekly.days_count'] ?? 1).toDouble();

    oldUser.forEach((key, value) {
      if (key.startsWith('weekly.') && key != 'weekly.days_count') {
        oldNormalized[key] =
            (value.toDouble()) / (oldDays == 0 ? 1 : oldDays);
      }
    });

    // ---- STEP 4: Get CURRENT data ----
    final currentDoc = await firestore
        .collection('competition')
        .doc(username)
        .get();

    final currentData = currentDoc.data() ?? {};

    // ---- STEP 5: Normalize CURRENT data ----
    Map<String, double> currentNormalized = {};

    double currentDays =
    (currentData['weekly.days_count'] ?? 1).toDouble();

    currentData.forEach((key, value) {
      if (key.startsWith('weekly.') && key != 'weekly.days_count') {
        currentNormalized[key] =
            (value.toDouble()) / (currentDays == 0 ? 1 : currentDays);
      }
    });

    // ---- STEP 6: Calculate % change ----
    Map<String, double> percentageChange = {};

    oldNormalized.forEach((key, oldVal) {
      double currentVal = currentNormalized[key] ?? 0;

      double percent;

      if (oldVal == 0 && currentVal > 0) {
        percent = 100;
      } else if (oldVal == 0 && currentVal == 0) {
        percent = 0;
      } else {
        percent = ((currentVal - oldVal) / oldVal) * 100;
      }

      percentageChange[key] = percent;
    });

    return percentageChange;
  }

  /// Monthly percentage change
  Future<Map<String, double>> getMonthlyPercentageChange({
    required String username,
  }) async {
    // ---- STEP 1: Get last finalized month ----
    final metaDoc = await firestore
        .collection('competition-results')
        .doc('monthly_meta')
        .get();

    final lastMonthId = metaDoc.data()?['last_month_finalized'];

    if (lastMonthId == null) {
      return {};
    }

    // ---- STEP 2: Get previous month data ----
    final monthDoc = await firestore
        .collection('competition-results')
        .doc('monthly-participants')
        .collection('months')
        .doc(lastMonthId)
        .get();

    List participants = monthDoc.data()?['participants'] ?? [];

    Map<String, dynamic>? oldUser;

    for (var p in participants) {
      if (p['username'] == username) {
        oldUser = p;
        break;
      }
    }

    if (oldUser == null) {
      return {};
    }

    // ---- STEP 3: Normalize OLD data ----
    Map<String, double> oldNormalized = {};

    double oldDays =
    (oldUser['monthly.days_count'] ?? 1).toDouble();

    oldUser.forEach((key, value) {
      if (key.startsWith('monthly.') && key != 'monthly.days_count') {
        oldNormalized[key] =
            (value.toDouble()) / (oldDays == 0 ? 1 : oldDays);
      }
    });

    // ---- STEP 4: Get CURRENT data ----
    final currentDoc = await firestore
        .collection('competition')
        .doc(username)
        .get();

    final currentData = currentDoc.data() ?? {};

    // ---- STEP 5: Normalize CURRENT data ----
    Map<String, double> currentNormalized = {};

    double currentDays =
    (currentData['monthly.days_count'] ?? 1).toDouble();

    currentData.forEach((key, value) {
      if (key.startsWith('monthly.') && key != 'monthly.days_count') {
        currentNormalized[key] =
            (value.toDouble()) / (currentDays == 0 ? 1 : currentDays);
      }
    });

    // ---- STEP 6: Calculate % change ----
    Map<String, double> percentageChange = {};

    oldNormalized.forEach((key, oldVal) {
      double currentVal = currentNormalized[key] ?? 0;

      double percent;

      if (oldVal == 0 && currentVal > 0) {
        percent = 100;
      } else if (oldVal == 0 && currentVal == 0) {
        percent = 0;
      } else {
        percent = ((currentVal - oldVal) / oldVal) * 100;
      }

      percentageChange[key] = percent;
    });

    return percentageChange;
  }

}
