import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patient dashboard has one authorised mode switch and Corvia logo', () {
    final source = File(
      'lib/pages/patient/dashboard.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect("tooltip: 'Switch Mode'".allMatches(source).length, 1);
    expect(source, isNot(contains("title: 'Switch Mode'")));
    expect(source, contains('AccountModeService.current()'));
    expect(source, contains('access.canSwitchClinicalPatient'));
    expect(source, contains('CorviaLogo('));
    expect(pubspec, contains('- assets/icon/corvia_mark.svg'));
    expect(File('assets/icon/corvia_mark.svg').existsSync(), isTrue);
  });
}
