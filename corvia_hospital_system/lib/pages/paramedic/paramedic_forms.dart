import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/paramedic_workspace_service.dart';

class EmsField {
  const EmsField(this.key, this.label,
      {this.required = false,
      this.options,
      this.number = false,
      this.integer = false,
      this.multiline = false,
      this.date = false,
      this.time = false,
      this.secret = false,
      this.max = 150});
  final String key, label;
  final bool required, number, integer, multiline, date, time, secret;
  final int max;
  final Map<String, String>? options;
}

Map<String, String> choices(List<String> values) =>
    {for (final v in values) v: v};
final emsPriority = choices(['Critical', 'High', 'Medium', 'Low']);
final emsSeverity = choices(['Low', 'Medium', 'High', 'Critical']);

List<EmsField> emsFields(String action) => switch (action) {
      'unit' => const [
          EmsField('unit_number', 'Call sign / unit number',
              required: true, max: 50),
          EmsField('registration_number', 'Registration number',
              required: true, max: 30),
          EmsField('vehicle_type', 'Vehicle type', required: true, max: 50),
          EmsField('base_location', 'Base location'),
          EmsField('response_capability', 'Response capability',
              required: true,
              options: {
                'BLS': 'BLS — Basic Life Support',
                'ILS': 'ILS — Intermediate Life Support',
                'ALS': 'ALS — Advanced Life Support'
              }),
          EmsField('compliance_expiry_date', 'Vehicle compliance expiry',
              required: true, date: true)
        ],
      'member' => [
          const EmsField('employee_number', 'Staff number',
              required: true, max: 50),
          const EmsField('first_name', 'First name', required: true, max: 100),
          const EmsField('last_name', 'Surname', required: true, max: 100),
          const EmsField('email', 'Existing account email', required: true),
          const EmsField('phone_number', 'Phone number', max: 30),
          const EmsField('qualification', 'Qualification / registration',
              required: true, max: 100),
          EmsField('verification_status', 'Credential status',
              required: true,
              options:
                  choices(['pending', 'verified', 'suspended', 'expired'])),
          const EmsField('verification_expiry_date', 'Credential expiry',
              date: true),
          EmsField('clinical_category', 'Clinical category',
              required: true, options: choices(['BLS', 'ILS', 'ALS'])),
          const EmsField('credential_evidence',
              'Verification evidence / registration reference',
              multiline: true, max: 1000),
          EmsField('is_active', 'Active staff member',
              required: true, options: choices(['true', 'false']))
        ],
      'facility' => const [
          EmsField('facility_code', 'Facility code', required: true, max: 50),
          EmsField('facility_name', 'Facility name', required: true, max: 200),
          EmsField('address', 'Address', max: 300),
          EmsField('phone_number', 'Phone number', max: 30),
          EmsField('emergency_department', 'Receiving department')
        ],
      'incident' => [
          EmsField('required_capability', 'Required response capability',
              required: true, options: choices(['BLS', 'ILS', 'ALS'])),
          EmsField('priority', 'Priority',
              required: true, options: emsPriority),
          const EmsField('incident_type', 'Incident type',
              required: true, max: 100),
          const EmsField('dispatch_notes', 'Dispatch notes',
              required: true, multiline: true, max: 2000),
          const EmsField('scene_address', 'Scene address',
              required: true, max: 300),
          const EmsField('latitude', 'Latitude (optional)', number: true),
          const EmsField('longitude', 'Longitude (optional)', number: true)
        ],
      'patient' => [
          const EmsField(
              'patient_number', 'Patient number (leave blank to generate)',
              max: 50),
          const EmsField('identity_number', 'ID / passport number', max: 50),
          const EmsField('first_name', 'First name / Unknown if unidentified',
              required: true, max: 100),
          const EmsField('last_name', 'Surname', max: 100),
          const EmsField('date_of_birth', 'Date of birth', date: true),
          EmsField('sex', 'Sex',
              options: choices(['Female', 'Male', 'Intersex', 'Unknown'])),
          EmsField('patient_recorded_blood_type',
              'Patient-reported blood type (unverified)',
              options: choices([
                'Unknown',
                'A+',
                'A-',
                'B+',
                'B-',
                'AB+',
                'AB-',
                'O+',
                'O-'
              ]))
        ],
      'patient_link' => const [
          EmsField('identifier', 'Exact patient number or ID / passport',
              required: true, max: 50)
        ],
      'hazard' => [
          const EmsField('hazard_type', 'Hazard type',
              required: true, max: 100),
          EmsField('severity', 'Severity',
              required: true, options: emsSeverity),
          const EmsField('description', 'Details',
              required: true, multiline: true, max: 500)
        ],
      'observation' => const [
          EmsField('heart_rate', 'Heart rate (bpm)', integer: true),
          EmsField('respiratory_rate', 'Respiratory rate (/min)',
              integer: true),
          EmsField('systolic_bp', 'Systolic BP (mmHg)', integer: true),
          EmsField('diastolic_bp', 'Diastolic BP (mmHg)', integer: true),
          EmsField('spo2', 'SpO₂ (%)', number: true),
          EmsField('temperature', 'Temperature (°C)', number: true),
          EmsField('gcs', 'GCS (3–15)', integer: true),
          EmsField('notes', 'Observation notes', multiline: true, max: 1000)
        ],
      'note' => const [
          EmsField('note_text', 'Clinical note / dated correction',
              required: true, multiline: true, max: 4000)
        ],
      'treatment' => const [
          EmsField('treatment_type', 'Treatment performed', required: true),
          EmsField('description', 'Details',
              required: true, multiline: true, max: 1000),
          EmsField('outcome', 'Outcome', multiline: true, max: 500)
        ],
      'allergy' => [
          const EmsField('allergen', 'Allergen', required: true),
          const EmsField('reaction', 'Reaction', max: 300),
          EmsField('severity', 'Severity', options: emsSeverity)
        ],
      'medication' => const [
          EmsField('medication_name', 'Medication', required: true),
          EmsField('dosage', 'Dosage', max: 100),
          EmsField('frequency', 'Frequency', max: 100),
          EmsField('notes', 'Notes', multiline: true, max: 500)
        ],
      'condition' => [
          const EmsField('condition_name', 'Condition', required: true),
          EmsField('severity', 'Severity', options: emsSeverity),
          const EmsField('notes', 'Notes', multiline: true, max: 500)
        ],
      'contact' => const [
          EmsField('name', 'Contact name', required: true),
          EmsField('relationship', 'Relationship', max: 100),
          EmsField('phone_number', 'Phone number', required: true, max: 30)
        ],
      'risk' => [
          const EmsField('risk_type', 'Special risk', required: true, max: 100),
          EmsField('severity', 'Severity', options: emsSeverity),
          const EmsField('description', 'Details', multiline: true, max: 500)
        ],
      'location' => const [
          EmsField('latitude', 'Latitude', required: true, number: true),
          EmsField('longitude', 'Longitude', required: true, number: true),
          EmsField('address', 'Address', max: 300),
          EmsField('location_type', 'Location type', required: true, max: 50)
        ],
      'handover' => const [
          EmsField('receiver_name', 'Receiving clinician name', required: true),
          EmsField('receiver_role', 'Receiving clinician role',
              required: true, max: 100),
          EmsField('handover_summary', 'Clinical handover summary',
              required: true, multiline: true, max: 4000),
          EmsField('notes', 'Additional notes', multiline: true, max: 1000)
        ],
      _ => const [],
    };

String emsLabel(String value) =>
    const {
      'heart_rate': 'Heart rate (bpm)',
      'respiratory_rate': 'Respiratory rate (/min)',
      'systolic_bp': 'Systolic BP (mmHg)',
      'diastolic_bp': 'Diastolic BP (mmHg)',
      'spo2': 'SpO₂ (%)',
      'temperature': 'Temperature (°C)',
      'gcs': 'GCS',
    }[value] ??
    value
        .split('_')
        .map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');

/// Server timestamps are UTC; input and display are explicitly SAST on every device.
String emsTime(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')
      ?.toUtc()
      .add(const Duration(hours: 2));
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} SAST';
}

DateTime? emsInputDate(String value, {required bool time}) {
  final match = RegExp(time
          ? r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$'
          : r'^(\d{4})-(\d{2})-(\d{2})$')
      .firstMatch(value);
  if (match == null) return null;
  final y = int.parse(match[1]!),
      m = int.parse(match[2]!),
      d = int.parse(match[3]!);
  final hour = time ? int.parse(match[4]!) : 0,
      minute = time ? int.parse(match[5]!) : 0;
  final date = DateTime.utc(y, m, d, hour, minute);
  if (date.year != y ||
      date.month != m ||
      date.day != d ||
      date.hour != hour ||
      date.minute != minute) {
    return null;
  }
  return time ? date.subtract(const Duration(hours: 2)) : date;
}

class EmsFormDialog extends StatefulWidget {
  const EmsFormDialog(
      {super.key,
      required this.title,
      required this.fields,
      required this.save,
      this.initial = const {}});
  final String title;
  final List<EmsField> fields;
  final EmsRow initial;
  final Future<EmsRow> Function(EmsRow, String) save;
  @override
  State<EmsFormDialog> createState() => _EmsFormDialogState();
}

class _EmsFormDialogState extends State<EmsFormDialog> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selected = {};
  bool _busy = false;
  bool _uncertain = false;
  String? _error;
  String _operation = emsOperationId();
  EmsRow? _submitted;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      var value = widget.initial[f.key]?.toString() ?? '';
      if (f.time && value.isNotEmpty) {
        value = emsTime(value).replaceAll(' SAST', '');
      }
      if (f.options != null) {
        if (f.options!.containsKey(value)) _selected[f.key] = value;
      } else {
        _controllers[f.key] = TextEditingController(text: value);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_uncertain && !_form.currentState!.validate()) return;
    final EmsRow data = _uncertain ? EmsRow.from(_submitted!) : {};
    if (!_uncertain) {
      for (final f in widget.fields) {
        final v =
            (f.options != null ? _selected[f.key] : _controllers[f.key]?.text)
                    ?.trim() ??
                '';
        if (v.isEmpty) continue;
        data[f.key] = f.integer
            ? int.parse(v)
            : f.number
                ? double.parse(v)
                : f.time
                    ? emsInputDate(v, time: true)!.toIso8601String()
                    : f.options != null && v == 'true'
                        ? true
                        : f.options != null && v == 'false'
                            ? false
                            : v;
      }
    }
    if (!_uncertain) _operation = emsOperationId();
    _submitted = data;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.save(data, _operation);
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) {
        final definitive = e is PostgrestException &&
            const {
              '22023',
              'P0001',
              '23505',
              '42501',
              '401',
              '403',
              'PGRST301',
              'PGRST302',
              'PGRST303'
            }.contains(e.code);
        setState(() {
          _uncertain = !definitive;
          _error = definitive
              ? emsError(e)
              : 'Outcome unknown. Refresh saved state after closing, or retry this exact action.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Form(
                          key: _form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final f in widget.fields)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: f.options != null
                                      ? DropdownButtonFormField<String>(
                                          initialValue: _selected[f.key],
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                              labelText: f.label),
                                          items: f.options!.entries
                                              .map((e) => DropdownMenuItem(
                                                  value: e.key,
                                                  child: Text(e.value,
                                                      overflow: TextOverflow
                                                          .ellipsis)))
                                              .toList(),
                                          onChanged: _busy || _uncertain
                                              ? null
                                              : (v) => setState(
                                                  () => _selected[f.key] = v!),
                                          validator: (v) =>
                                              f.required && v == null
                                                  ? 'Required'
                                                  : null)
                                      : TextFormField(
                                          controller: _controllers[f.key],
                                          obscureText: f.secret,
                                          enabled: !_busy && !_uncertain,
                                          maxLength: f.max,
                                          minLines: f.multiline ? 3 : 1,
                                          maxLines: f.multiline ? 5 : 1,
                                          keyboardType: f.number || f.integer
                                              ? const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true, signed: true)
                                              : TextInputType.text,
                                          decoration: InputDecoration(
                                              labelText: f.label,
                                              helperText: f.time
                                                  ? 'YYYY-MM-DD HH:MM • SAST'
                                                  : f.date
                                                      ? 'YYYY-MM-DD'
                                                      : null,
                                              suffixIcon: f.date || f.time
                                                  ? IconButton(
                                                      icon: const Icon(Icons.calendar_today),
                                                      onPressed: _busy || _uncertain
                                                          ? null
                                                          : () async {
                                                              final day = await showDatePicker(
                                                                  context:
                                                                      context,
                                                                  initialDate:
                                                                      DateTime
                                                                          .now(),
                                                                  firstDate:
                                                                      DateTime(
                                                                          1900),
                                                                  lastDate:
                                                                      DateTime(
                                                                          2100));
                                                              if (day == null ||
                                                                  !context
                                                                      .mounted ||
                                                                  _uncertain) {
                                                                return;
                                                              }
                                                              String value =
                                                                  '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                                                              if (f.time) {
                                                                final time = await showTimePicker(
                                                                    context:
                                                                        context,
                                                                    initialTime:
                                                                        TimeOfDay
                                                                            .now());
                                                                if (time ==
                                                                        null ||
                                                                    !context
                                                                        .mounted ||
                                                                    _uncertain) {
                                                                  return;
                                                                }
                                                                value +=
                                                                    ' ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                                              }
                                                              _controllers[
                                                                      f.key]!
                                                                  .text = value;
                                                            })
                                                  : null),
                                          validator: (raw) {
                                            final v = raw?.trim() ?? '';
                                            if (v.isEmpty) {
                                              return f.required
                                                  ? 'Required'
                                                  : null;
                                            }
                                            if (f.integer &&
                                                int.tryParse(v) == null) {
                                              return 'Enter a whole number';
                                            }
                                            if (f.number &&
                                                (double.tryParse(v) == null ||
                                                    !double.parse(v)
                                                        .isFinite)) {
                                              return 'Enter a number';
                                            }
                                            if ((f.date || f.time) &&
                                                emsInputDate(v, time: f.time) ==
                                                    null) {
                                              return 'Enter a valid date';
                                            }
                                            if (f.key ==
                                                'compliance_expiry_date') {
                                              final selected =
                                                  emsInputDate(v, time: false);
                                              final now = DateTime.now();
                                              final today = DateTime.utc(
                                                now.year,
                                                now.month,
                                                now.day,
                                              );
                                              if (selected != null &&
                                                  selected.isBefore(today)) {
                                                return 'Compliance expiry cannot be in the past';
                                              }
                                            }
                                            return null;
                                          })),
                            if (_error != null)
                              Text(_error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                          ]))))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy
                    ? 'Saving…'
                    : _uncertain
                        ? 'Retry same action'
                        : 'Save'))
          ]));
}

String emsError(Object e) {
  final text = e.toString();
  if (text.contains('corvia_ems_update_patient') &&
      (text.contains('schema cache') || text.contains('does not exist'))) {
    return 'Install supabase/scripts/workstreams/18_install_live_qa_fixes.sql in Supabase, then refresh.';
  }
  if (text.contains('corvia_ems_') &&
      (text.contains('schema cache') || text.contains('does not exist'))) {
    return 'Install the Fleet & Paramedic workspace SQL package in Supabase, then refresh.';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed to fetch')) {
    return 'Could not reach the server. Your form is still open; retry when connected.';
  }
  return text.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
}
