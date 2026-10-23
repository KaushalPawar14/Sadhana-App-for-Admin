import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/utils/StudentNameGuard.dart';

// Every place an admin creates a student trims the name the same way before saving: a student's
// name is the key of five collections, so "Dhiraj Kumar " and "Dhiraj Kumar" would be two folders.

void main() {
  group('normalizeStudentName', () {
    test('"  Ram Das  " is saved as "Ram Das"', () {
      expect(normalizeStudentName('  Ram Das  '), 'Ram Das');
    });
    test('a trailing or a leading space alone is removed; casing and inner words are kept', () {
      expect(normalizeStudentName('Ram Das '), 'Ram Das');
      expect(normalizeStudentName(' Ram Das'), 'Ram Das');
      expect(normalizeStudentName('Asha Rao Kumar'), 'Asha Rao Kumar');
      expect(normalizeStudentName('ram DAS'), 'ram DAS');
    });
    test('only spaces becomes empty', () {
      expect(normalizeStudentName('   '), '');
    });
  });

  group('source guarantee: each place a student is created normalises the name first', () {
    String read(String path) => File(path).readAsStringSync();

    test('Add Student / manual entry (BoysDetails) saves the normalised name', () {
      final s = read('lib/Pages/BoysDetails.dart');
      expect(s.contains('final name = normalizeStudentName(nameController.text);'), isTrue);
      expect(s.contains('name: name,'), isTrue); // handed to the shared write (actions/StudentActions.dart)
      final shared = read('lib/actions/StudentActions.dart');
      expect(shared.contains('final cleanName = normalizeStudentName(name);'), isTrue);
      expect(shared.contains("'name': cleanName,"), isTrue);
      expect(RegExp(r"final name = nameController\.text\.trim\(\);").hasMatch(s), isFalse);
    });

    test('admin registration (AdminRegisterUserPage) normalises before the name-taken check and the save', () {
      final s = read('lib/Pages/AdminRegisterUserPage.dart');
      final normalise = s.indexOf('final name = normalizeStudentName(nameController.text);');
      final taken = s.indexOf('isStudentNameTaken(name)');
      final save = s.indexOf("'name': name,");
      expect(normalise, greaterThan(-1));
      expect(taken, greaterThan(normalise));
      expect(save, greaterThan(taken));
    });

    test('no other screen writes a student name straight from a text field', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        if (RegExp(r"collection\('users'\)[\s\S]{0,200}?'name':\s*\w*[cC]ontroller\.text(?!\s*\.trim)").hasMatch(s)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
