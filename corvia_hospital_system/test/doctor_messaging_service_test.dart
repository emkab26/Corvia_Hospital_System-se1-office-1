import 'package:flutter_test/flutter_test.dart';
import 'package:mycorvia/services/doctor_messaging_service.dart';

void main() {
  group('DoctorMessagingService', () {
    test(
      'message maximum length remains 1000 characters',
      () {
        expect(
          DoctorMessagingService.messageMaxLength,
          1000,
        );
      },
    );

    test(
      'message maximum length is greater than zero',
      () {
        expect(
          DoctorMessagingService.messageMaxLength,
          greaterThan(0),
        );
      },
    );
  });
}