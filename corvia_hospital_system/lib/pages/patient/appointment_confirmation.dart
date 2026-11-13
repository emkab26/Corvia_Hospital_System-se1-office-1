import 'package:flutter/material.dart';

class AppointmentConfirmationPage extends StatelessWidget {
  final String doctorName;
  final String date;
  final String time;
  final String reason;

  const AppointmentConfirmationPage({
    super.key,
    required this.doctorName,
    required this.date,
    required this.time,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm Appointment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Doctor: $doctorName'),
            const SizedBox(height: 10),
            Text('Date: $date'),
            const SizedBox(height: 10),
            Text('Time: $time'),
            const SizedBox(height: 10),
            Text('Reason: $reason'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: Text('Confirm Booking'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
