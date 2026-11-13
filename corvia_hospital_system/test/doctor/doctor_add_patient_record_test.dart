import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mycorvia/pages/doctor/doctor_add_patient_record.dart';
import 'package:mycorvia/services/doctor_clinical_service.dart';

class _FakeDoctorClinicalService extends DoctorClinicalService {
  _FakeDoctorClinicalService() : super(client: Supabase.instance.client);

  @override
  Future<DoctorClinicalContext> currentContext() async {
    return const DoctorClinicalContext(
      doctorId: 'doctor-id',
      profileId: 'profile-id',
      authUserId: 'auth-user-id',
      doctorName: 'Dr. Test Doctor',
      hospitalId: 'hospital-id',
      departmentId: 'department-id',
    );
  }

  @override
  Future<DoctorClinicalCatalog> loadCatalog(
    DoctorClinicalContext context,
  ) async {
    return const DoctorClinicalCatalog(
      treatments: [
        'Physical Therapy',
        'Surgery',
      ],
      labTests: [
        'Blood Test',
        'MRI Scan',
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Future<void> loadForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AddPatientRecord(
          patientId: 'patient-id',
          service: _FakeDoctorClinicalService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads the current doctor record form', (tester) async {
    await loadForm(tester);

    expect(find.text('Add Patient Record'), findsOneWidget);
    expect(find.text('Dr. Test Doctor'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Add Diagnosis'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Add Clinical Note'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Result for Selected Test'),
      findsOneWidget,
    );
    expect(find.text('Save Patient Record'), findsOneWidget);
  });

  testWidgets('requires a treatment before saving', (tester) async {
    await loadForm(tester);

    await tester.tap(find.text('Save Patient Record'));
    await tester.pump();

    expect(find.text('Select a treatment.'), findsOneWidget);
  });

  testWidgets('adds, rejects duplicates and removes a diagnosis',
      (tester) async {
    await loadForm(tester);

    final diagnosisField = find.widgetWithText(TextField, 'Add Diagnosis');
    final diagnosisAdd = find.widgetWithIcon(FilledButton, Icons.add).first;

    await tester.enterText(diagnosisField, 'Hypertension');
    await tester.tap(diagnosisAdd);
    await tester.pump();

    expect(find.text('Hypertension'), findsOneWidget);

    await tester.enterText(diagnosisField, 'hypertension');
    await tester.tap(diagnosisAdd);
    await tester.pump();

    expect(find.text('Diagnosis already added.'), findsOneWidget);

    tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!.call();
    await tester.pump();

    expect(find.text('Hypertension'), findsNothing);
  });

  testWidgets('adds and removes a clinical note', (tester) async {
    await loadForm(tester);

    final noteField = find.widgetWithText(TextField, 'Add Clinical Note');
    final noteAdd = find.widgetWithIcon(FilledButton, Icons.add).at(1);

    await tester.enterText(noteField, 'Monitor blood pressure daily.');
    await tester.tap(noteAdd);
    await tester.pump();

    expect(find.text('Monitor blood pressure daily.'), findsOneWidget);

    tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!.call();
    await tester.pump();

    expect(find.text('Monitor blood pressure daily.'), findsNothing);
  });

  testWidgets('selects a treatment from the current catalogue', (tester) async {
    await loadForm(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Surgery').last);
    await tester.pumpAndSettle();

    final treatment = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(treatment.initialValue, 'Surgery');
    expect(find.text('Surgery'), findsOneWidget);
  });

  testWidgets('adds and removes a selected laboratory result', (tester) async {
    await loadForm(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MRI Scan').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Result for Selected Test'),
      'Clear',
    );
    await tester.tap(find.text('Add Result'));
    await tester.pump();

    expect(find.text('MRI Scan'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(find.text('Clear'), findsNothing);
  });
}
