import 'package:flutter/material.dart';

import '../../services/doctor_directory.dart';
import '../../theme/app_theme.dart';
import 'book_appointment.dart';
import 'chat_with_doctor.dart';

/// Detailed view of a doctor's profile showing comprehensive information
/// with options to chat or book an appointment.
class DoctorDetailPage extends StatelessWidget {
  const DoctorDetailPage({
    super.key,
    required this.doctor,
  });

  final DoctorEntry doctor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Doctor Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back to Directory',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Doctor Header Card
            Card(
              color: context.cBgSecondary,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: doctor.available
                          ? CorviaColors.success
                          : context.cTextMuted,
                      child: const Icon(
                        Icons.medical_services,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Doctor Name
                    Text(
                      doctor.displayName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Availability Status
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: doctor.available
                            ? CorviaColors.success.withAlpha(25)
                            : context.cTextMuted.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: doctor.available
                                  ? CorviaColors.success
                                  : context.cTextMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            doctor.available ? 'Available Now' : 'Unavailable',
                            style: TextStyle(
                              color: doctor.available
                                  ? CorviaColors.success
                                  : context.cTextMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Information Sections
            _InfoSection(
              icon: Icons.medical_information_outlined,
              title: 'Specialization',
              content: doctor.specialization.isNotEmpty
                  ? doctor.specialization
                  : 'General Practitioner',
            ),
            const SizedBox(height: 12),

            _InfoSection(
              icon: Icons.location_on_outlined,
              title: 'Location',
              content: doctor.location.isNotEmpty
                  ? doctor.location
                  : 'Location not specified',
            ),
            const SizedBox(height: 12),

            if (doctor.distanceLabel.isNotEmpty)
              Column(
                children: [
                  _InfoSection(
                    icon: Icons.directions_outlined,
                    title: 'Distance',
                    content: doctor.distanceLabel,
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            _InfoSection(
              icon: Icons.schedule_outlined,
              title: 'Working Hours',
              content:
                  '${doctor.workStart.format(context)} - ${doctor.workEnd.format(context)}',
            ),
            const SizedBox(height: 12),

            _InfoSection(
              icon: Icons.calendar_today_outlined,
              title: 'Working Days',
              content: _formatWorkingDays(doctor.workingDays),
            ),
            const SizedBox(height: 12),

            _InfoSection(
              icon: Icons.access_time_outlined,
              title: 'Appointment Duration',
              content: '${doctor.slotDurationMinutes} minutes',
            ),
            const SizedBox(height: 12),

            if (doctor.isVerified)
              Column(
                children: [
                  _InfoSection(
                    icon: Icons.verified_outlined,
                    title: 'Verification',
                    content: 'Verified Professional',
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            // Action Buttons
            const SizedBox(height: 24),
            Row(
              children: [
                if (doctor.available)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChatWithDoctorPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat'),
                    ),
                  ),
                if (doctor.available) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: doctor.available
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BookingApp(),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Book'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatWorkingDays(List<int> days) {
    const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final formatted = days.map((day) => dayNames[day]).join(', ');
    return formatted.isNotEmpty ? formatted : 'Not specified';
  }
}

/// Reusable information section widget
class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.cBgSecondary,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: CorviaColors.accentLight,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
