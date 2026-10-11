import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The one place the app asks for its Firestore. In the app it is simply
/// `FirebaseFirestore.instance`; a test can swap in an in-memory database
/// (`fake_cloud_firestore`) so a whole screen can be pumped with real data shapes.
/// No query, read or write changes — only where the instance comes from.
class GuideDb {
  GuideDb._();

  static FirebaseFirestore? _override;

  static FirebaseFirestore get instance => _override ?? FirebaseFirestore.instance;

  @visibleForTesting
  static void useForTests(FirebaseFirestore? db) => _override = db;
}
