/// Pure-Dart data models for the Doctor Report feature.
/// No Flutter imports - keeps models testable and portable.
library;

enum VitalStatus { normal, warning, critical }

// ── Patient ──────────────────────────────────────────────────────────────────

class PatientData {
  final String fullName;
  final String initials;
  final String gender;
  final String age;
  final String bloodType;
  final String patientId;
  final String phone;

  const PatientData({
    required this.fullName,
    required this.initials,
    required this.gender,
    required this.age,
    required this.bloodType,
    required this.patientId,
    required this.phone,
  });
}

// ── Vitals ───────────────────────────────────────────────────────────────────

class VitalData {
  final String label;
  final String value;
  final String unit;
  final VitalStatus status;

  /// Maps to an icon in the widget layer. Keeps models Flutter-free.
  /// Valid keys: 'heart' | 'speed' | 'thermostat' | 'air' | 'waves' | 'water'
  final String iconKey;

  const VitalData({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.iconKey,
  });
}

// ── Diagnosis ────────────────────────────────────────────────────────────────

class DiagnosisData {
  final String icdCode;
  final String name;
  final bool isPrimary;

  const DiagnosisData({
    required this.icdCode,
    required this.name,
    required this.isPrimary,
  });
}

// ── Medication ───────────────────────────────────────────────────────────────

class MedicationData {
  final String name;
  final String dosage;
  final String frequency;
  final String duration;

  const MedicationData({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.duration,
  });
}

// ── Clinical Notes ────────────────────────────────────────────────────────────

class ClinicalNotesData {
  final String doctorName;
  final String doctorSpecialty;
  final String hospital;
  final String notes;

  const ClinicalNotesData({
    required this.doctorName,
    required this.doctorSpecialty,
    required this.hospital,
    required this.notes,
  });
}

// ── Follow-Up ─────────────────────────────────────────────────────────────────

class FollowUpData {
  final String dateTime;
  final String location;

  const FollowUpData({
    required this.dateTime,
    required this.location,
  });
}

// ── Root container ────────────────────────────────────────────────────────────

class ReportData {
  final String visitDate;
  final PatientData patient;
  final List<VitalData> vitals;
  final List<DiagnosisData> diagnoses;
  final List<MedicationData> medications;
  final ClinicalNotesData clinicalNotes;
  final FollowUpData followUp;

  const ReportData({
    required this.visitDate,
    required this.patient,
    required this.vitals,
    required this.diagnoses,
    required this.medications,
    required this.clinicalNotes,
    required this.followUp,
  });

  /// Sample data used during development and on the dashboard "Preview" button.
  factory ReportData.sample() => const ReportData(
        visitDate: '10 June 2026',
        patient: PatientData(
          fullName: 'Themba Molefe',
          initials: 'TM',
          gender: 'Male',
          age: '47 yrs',
          bloodType: 'B+',
          patientId: 'PT-2024-00847',
          phone: '+27 82 345 6789',
        ),
        vitals: [
          VitalData(
            label: 'Heart Rate',
            value: '88',
            unit: 'bpm',
            status: VitalStatus.normal,
            iconKey: 'heart',
          ),
          VitalData(
            label: 'Blood Pressure',
            value: '142/91',
            unit: 'mmHg',
            status: VitalStatus.warning,
            iconKey: 'speed',
          ),
          VitalData(
            label: 'Temperature',
            value: '37.2',
            unit: '°C',
            status: VitalStatus.normal,
            iconKey: 'thermostat',
          ),
          VitalData(
            label: 'SpO₂',
            value: '97',
            unit: '%',
            status: VitalStatus.normal,
            iconKey: 'air',
          ),
          VitalData(
            label: 'Resp. Rate',
            value: '18',
            unit: '/min',
            status: VitalStatus.normal,
            iconKey: 'waves',
          ),
          VitalData(
            label: 'Blood Glucose',
            value: '7.8',
            unit: 'mmol/L',
            status: VitalStatus.warning,
            iconKey: 'water',
          ),
        ],
        diagnoses: [
          DiagnosisData(
            icdCode: 'I10',
            name: 'Essential (primary) hypertension',
            isPrimary: true,
          ),
          DiagnosisData(
            icdCode: 'E11.9',
            name: 'Type 2 diabetes mellitus without complications',
            isPrimary: false,
          ),
          DiagnosisData(
            icdCode: 'Z82.49',
            name: 'Family history of ischaemic heart disease',
            isPrimary: false,
          ),
        ],
        medications: [
          MedicationData(
            name: 'Amlodipine',
            dosage: '5 mg',
            frequency: 'Once daily',
            duration: '30 days',
          ),
          MedicationData(
            name: 'Metformin HCl',
            dosage: '500 mg',
            frequency: 'Twice daily with meals',
            duration: '30 days',
          ),
          MedicationData(
            name: 'Aspirin (low-dose)',
            dosage: '100 mg',
            frequency: 'Once daily at night',
            duration: '90 days',
          ),
        ],
        clinicalNotes: ClinicalNotesData(
          doctorName: 'Dr. Naledi Dlamini',
          doctorSpecialty: 'Cardiologist',
          hospital: 'Steve Biko Academic Hospital',
          notes:
              'Patient presents with elevated blood pressure (142/91 mmHg) and '
              'mildly elevated fasting blood glucose. Reports occasional headaches '
              'and fatigue over the past 3 weeks. No chest pain or dyspnoea reported.\n\n'
              'Physical examination unremarkable apart from BP findings. BMI 27.4 - '
              'patient counselled on weight management and sodium reduction. Lifestyle '
              'modification discussed including dietary changes and structured aerobic '
              'exercise (30 min, 5×/week).\n\n'
              'Initiated Amlodipine for BP control. Metformin continued at current '
              'dose with review in 4 weeks. Patient instructed to monitor BP at home '
              'twice daily.',
        ),
        followUp: FollowUpData(
          dateTime: 'Tuesday, 8 July 2026 · 09:30 AM',
          location: 'Cardiology Outpatient Clinic - Room 4B',
        ),
      );
}
