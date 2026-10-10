import 'package:cloud_firestore/cloud_firestore.dart';

/// A document with plain data, for widget tests.
class FakeDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  FakeDoc(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic> data() => _data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A query snapshot with plain documents, for widget tests.
class FakeSnap implements QuerySnapshot<Map<String, dynamic>> {
  FakeSnap(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
