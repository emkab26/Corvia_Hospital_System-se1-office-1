import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AiSymptomIntakePage extends StatefulWidget {
  const AiSymptomIntakePage({super.key});

  @override
  State<AiSymptomIntakePage> createState() => _AiSymptomIntakePageState();
}

class _AiSymptomIntakePageState extends State<AiSymptomIntakePage> {
  final TextEditingController _symptomsController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _medicationController = TextEditingController();

  String _summary = '';

  void _generateSummary() {
    final symptoms = _symptomsController.text.trim();
    final duration = _durationController.text.trim();
    final medication = _medicationController.text.trim();

    setState(() {
      _summary = '''
Patient Symptom Intake Summary

Symptoms:
${symptoms.isEmpty ? 'Not provided' : symptoms}

Duration:
${duration.isEmpty ? 'Not provided' : duration}

Current Medication:
${medication.isEmpty ? 'Not provided' : medication}

AI Notes:
• Patient symptoms have been captured.
• Doctor should review before consultation.
• Monitor if symptoms become worse.
• Seek urgent medical help for chest pain, breathing difficulty, fainting, severe allergic reaction, or sudden weakness.
''';
    });
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    _durationController.dispose();
    _medicationController.dispose();
    super.dispose();
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: CorviaColors.textSecondary),
      filled: true,
      fillColor: Colors.white10,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: CorviaColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: CorviaColors.accentLight),
      ),
    );
  }

  Widget _characterCounter(TextEditingController controller) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${value.text.length} characters',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('AI Symptom Intake'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.psychology,
              size: 72,
              color: CorviaColors.accentLight,
            ),
            const SizedBox(height: 12),
            Text(
              'Pre-Consultation Intake',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Capture symptoms before the doctor sees the patient.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _symptomsController,
              maxLines: 5,
              style: TextStyle(color: context.cTextPrimary),
              decoration: _input('Describe symptoms'),
            ),
            _characterCounter(_symptomsController),
            const SizedBox(height: 14),
            TextField(
              controller: _durationController,
              style: TextStyle(color: context.cTextPrimary),
              decoration: _input('How long has this been happening?'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _medicationController,
              maxLines: 3,
              style: TextStyle(color: context.cTextPrimary),
              decoration: _input('Current medication or allergies'),
            ),
            _characterCounter(_medicationController),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generateSummary,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Intake Summary'),
              ),
            ),
            const SizedBox(height: 20),
            if (_summary.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CorviaColors.divider),
                ),
                child: SelectableText(
                  _summary,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
