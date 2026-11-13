import 'package:flutter/material.dart';

class HospitalFeaturePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String moduleStatus;
  final List<HospitalFeatureSection> sections;

  const HospitalFeaturePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.moduleStatus,
    required this.sections,
  });

  static const Color primary = Color(0xFF0F172A);
  static const Color accent = Color(0xFF06B6D4);
  static const Color background = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF111827);
  static const Color mutedText = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to hospital dashboard',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: primary,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: textDark,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: mutedText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        moduleStatus,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ...sections.map(
                (section) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: section.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          section.icon,
                          color: section.color,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.title,
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              section.description,
                              style: const TextStyle(
                                color: mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}

class HospitalFeatureSection {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const HospitalFeatureSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
