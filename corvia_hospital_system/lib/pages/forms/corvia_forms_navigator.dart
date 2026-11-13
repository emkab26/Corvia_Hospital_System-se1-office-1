import 'package:flutter/material.dart';
import 'role_hospital_forms_page.dart';

class CorviaFormsNavigator {
  const CorviaFormsNavigator._();

  static Future<void> openCurrentUserForms(
    BuildContext context,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return const RoleHospitalFormsPage();
        },
      ),
    );
  }

  static Future<void> openPatientForms(
    BuildContext context, {
    required String patientId,
    String? hospitalId,
    String? admissionId,
    String? contextType,
    String? contextId,
    String title = 'Patient Hospital Forms',
    String? routeName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: routeName ?? title),
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: contextType,
            contextId: contextId,
            title: title,
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openPatientVisibleForms(
    BuildContext context, {
    String? hospitalId,
    String? patientId,
    String? admissionId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            title: 'My Hospital Forms',
            patientVisibleOnly: true,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openAdmissionForms(
    BuildContext context, {
    required String patientId,
    required String admissionId,
    String? hospitalId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: 'admission',
            contextId: admissionId,
            title: 'Admission and Consent Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openAppointmentForms(
    BuildContext context, {
    required String patientId,
    required String appointmentId,
    String? hospitalId,
    String? admissionId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: 'appointment',
            contextId: appointmentId,
            title: 'Appointment Clinical Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openEmergencyForms(
    BuildContext context, {
    required String patientId,
    String? hospitalId,
    String? admissionId,
    String? emergencyContextId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: 'emergency',
            contextId: emergencyContextId,
            title: 'Emergency and Casualty Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openNursingForms(
    BuildContext context, {
    required String patientId,
    String? hospitalId,
    String? admissionId,
    String? assignmentId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: 'nurse_assignment',
            contextId: assignmentId,
            title: 'Nursing Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openPharmacyForms(
    BuildContext context, {
    required String patientId,
    String? hospitalId,
    String? prescriptionId,
    String? dispenseId,
  }) {
    final contextId = dispenseId ?? prescriptionId;

    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            contextType:
                dispenseId != null ? 'prescription_dispense' : 'prescription',
            contextId: contextId,
            title: 'Pharmacy Dispensing Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openTransferForms(
    BuildContext context, {
    required String patientId,
    required String transferId,
    String? hospitalId,
    String? admissionId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            patientId: patientId,
            admissionId: admissionId,
            contextType: 'interhospital_transfer',
            contextId: transferId,
            title: 'Patient Transfer Forms',
            patientVisibleOnly: false,
            allowCreate: true,
          );
        },
      ),
    );
  }

  static Future<void> openHospitalFormLibrary(
    BuildContext context, {
    String? hospitalId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return RoleHospitalFormsPage(
            hospitalId: hospitalId,
            title: 'Hospital Form Library',
            patientVisibleOnly: false,
            allowCreate: false,
          );
        },
      ),
    );
  }
}
