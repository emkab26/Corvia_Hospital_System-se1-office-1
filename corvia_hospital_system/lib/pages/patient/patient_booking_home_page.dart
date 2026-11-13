import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'book_appointment.dart';
import 'specialist/specialist_request_page.dart';

class PatientBookingHomePage extends StatelessWidget {
  const PatientBookingHomePage({super.key});

  Future<void> _openPage(
    BuildContext context,
    Widget page,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Book Appointment'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              32,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 950,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What type of appointment do you need?',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Book an available general doctor directly, '
                        'or send a specialist request to reception.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, cardConstraints) {
                          if (cardConstraints.maxWidth >= 700) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _BookingTypeCard(
                                    icon: Icons.medical_services_outlined,
                                    title: 'General Doctor',
                                    subtitle: 'Choose an available doctor, '
                                        'date and time. The appointment '
                                        'is booked immediately.',
                                    buttonLabel: 'Book General Doctor',
                                    color: CorviaColors.accent,
                                    onTap: () {
                                      _openPage(
                                        context,
                                        const BookingApp(),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _BookingTypeCard(
                                    icon: Icons.health_and_safety_outlined,
                                    title: 'Specialist',
                                    subtitle:
                                        'Choose a specialty and preferred '
                                        'hospital, date and time. Reception '
                                        'will assign and confirm the specialist.',
                                    buttonLabel: 'Request Specialist',
                                    color: Colors.deepPurple,
                                    onTap: () {
                                      _openPage(
                                        context,
                                        const SpecialistRequestPage(),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              _BookingTypeCard(
                                icon: Icons.medical_services_outlined,
                                title: 'General Doctor',
                                subtitle: 'Choose an available doctor, date '
                                    'and time. The appointment is booked '
                                    'immediately.',
                                buttonLabel: 'Book General Doctor',
                                color: CorviaColors.accent,
                                onTap: () {
                                  _openPage(
                                    context,
                                    const BookingApp(),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              _BookingTypeCard(
                                icon: Icons.health_and_safety_outlined,
                                title: 'Specialist',
                                subtitle: 'Choose a specialty and preferred '
                                    'hospital, date and time. Reception '
                                    'will assign and confirm the specialist.',
                                buttonLabel: 'Request Specialist',
                                color: Colors.deepPurple,
                                onTap: () {
                                  _openPage(
                                    context,
                                    const SpecialistRequestPage(),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Specialist requests begin as Pending. '
                                'Reception will assign a suitable specialist '
                                'and confirm or reschedule the appointment. '
                                'You will receive an in-app notification.',
                                style: TextStyle(
                                  color: context.cTextPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingTypeCard extends StatelessWidget {
  const _BookingTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: buttonLabel,
      child: Material(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: 260,
            ),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 29,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                    ),
                    label: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
