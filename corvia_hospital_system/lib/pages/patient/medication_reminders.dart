import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';

class MedicationRemindersPage extends StatefulWidget {
  const MedicationRemindersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<MedicationRemindersPage> createState() =>
      _MedicationRemindersPageState();
}

class _MedicationRemindersPageState extends State<MedicationRemindersPage> {
  static const String _customMedicationValue = 'custom';

  final TextEditingController _medController = TextEditingController();
  final List<_MedicationReminderItem> _reminders = [];
  final List<_PrescribedMedication> _prescribedMedications = [];

  bool _loading = true;
  bool _saving = false;
  String _selectedMedicationValue = _customMedicationValue;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();

    _loadReminders();
  }

  @override
  void dispose() {
    _medController.dispose();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    setState(() {
      _loading = true;
    });

    try {
      final patientId = await SupabaseService.currentPatientId();

      if (patientId == null) {
        if (!mounted) return;
        setState(() {
          _reminders.clear();
          _loading = false;
        });
        return;
      }

      final rows = await SupabaseService.client
          .from('medication_reminders')
          .select(
            'id, medication_name, dosage, time_of_day, reminder_time, is_active, created_at',
          )
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);

      final prescribedMedications = await _loadPrescribedMedications(
        patientId,
      );

      final loaded = <_MedicationReminderItem>[];

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);

        loaded.add(
          _MedicationReminderItem(
            id: row['id']?.toString() ?? '',
            medicationName: row['medication_name']?.toString() ?? '',
            dosage: row['dosage']?.toString(),
            timeOfDay: row['time_of_day']?.toString() ?? 'Reminder',
            reminderTime: row['reminder_time']?.toString(),
            isActive: row['is_active'] == true,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _reminders
          ..clear()
          ..addAll(loaded);
        _prescribedMedications
          ..clear()
          ..addAll(prescribedMedications);

        final selectedStillExists = _selectedMedicationValue ==
                _customMedicationValue ||
            _prescribedMedications.any(
              (medication) => medication.value == _selectedMedicationValue,
            );

        if (!selectedStillExists) {
          _selectedMedicationValue = _customMedicationValue;
          _medController.clear();
        }
      });

      // The reminders live on the server but the alarms live on this device, so
      // a fresh install or a cleared app has rows with nothing scheduled behind
      // them. Re-arm from the source of truth on every load.
      for (final reminder in loaded) {
        await _syncNotification(reminder);
      }
    } catch (e) {
      debugPrint('Medication reminders load failed: $e');

      if (mounted) {
        _snack("Couldn't load medication reminders.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<List<_PrescribedMedication>> _loadPrescribedMedications(
    String patientId,
  ) async {
    try {
      final rows = await SupabaseService.client
          .from('prescriptions')
          .select(
            'id, medication_name, dosage, medicines, status, end_date, issued_at',
          )
          .eq('patient_id', patientId)
          .eq('status', 'active')
          .order('issued_at', ascending: false);

      final byName = <String, _PrescribedMedication>{};

      void addMedication(
        dynamic rawName,
        dynamic rawDosage,
      ) {
        final name = rawName?.toString().trim() ?? '';

        if (name.isEmpty || name.toLowerCase() == 'null') {
          return;
        }

        final dosage = rawDosage?.toString().trim();
        final key = name.toLowerCase();

        byName.putIfAbsent(
          key,
          () => _PrescribedMedication(
            value: 'prescribed:$key',
            name: name,
            dosage: dosage == null ||
                    dosage.isEmpty ||
                    dosage.toLowerCase() == 'null'
                ? null
                : dosage,
          ),
        );
      }

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final endDate = DateTime.tryParse(
          row['end_date']?.toString() ?? '',
        );

        if (endDate != null &&
            DateUtils.dateOnly(endDate).isBefore(
              DateUtils.dateOnly(DateTime.now()),
            )) {
          continue;
        }

        final medicines = row['medicines'];

        if (medicines is List) {
          for (final rawMedicine in medicines.whereType<Map>()) {
            addMedication(
              rawMedicine['name'] ?? rawMedicine['medication_name'],
              rawMedicine['dosage'],
            );
          }
        }

        addMedication(
          row['medication_name'],
          row['dosage'],
        );
      }

      final medications = byName.values.toList()
        ..sort(
          (first, second) => first.name.toLowerCase().compareTo(
                second.name.toLowerCase(),
              ),
        );

      return medications;
    } catch (error) {
      debugPrint(
        'Prescribed medications lookup failed: $error',
      );
      return const [];
    }
  }

  /// Brings the device alarm in line with the reminder row: scheduled when the
  /// reminder is active and its time parses, cancelled otherwise.
  Future<void> _syncNotification(_MedicationReminderItem reminder) async {
    if (reminder.id.isEmpty) return;

    final time = NotificationService.parseReminderTime(reminder.reminderTime);

    if (!reminder.isActive || time == null) {
      await NotificationService.instance.cancelMedicationReminder(reminder.id);
      return;
    }

    await NotificationService.instance.scheduleDailyMedicationReminder(
      reminderId: reminder.id,
      medicationName: reminder.medicationName,
      hour: time.hour,
      minute: time.minute,
    );
  }

  Future<void> _addReminder() async {
    final med = _medController.text.trim();

    if (med.isEmpty) {
      _snack('Enter a medication name first.');
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final patientId = await SupabaseService.currentPatientId();

      if (patientId == null) {
        _snack('Patient profile not found. Please login again.');
        return;
      }

      final reminderTime = _databaseTime(
        _selectedTime,
      );
      final timeOfDay = _timeOfDayLabel(
        _selectedTime,
      );
      final selectedMedication = _selectedPrescribedMedication;

      final created = await SupabaseService.client
          .from('medication_reminders')
          .insert({
            'patient_id': patientId,
            'medication_name': med,
            'dosage': selectedMedication?.dosage,
            'time_of_day': timeOfDay,
            'reminder_time': reminderTime,
            'repeat_days': const [
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
              'Sun'
            ],
            'is_active': true,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();

      final id = created['id']?.toString() ?? '';

      if (!mounted) return;

      final item = _MedicationReminderItem(
        id: id,
        medicationName: med,
        dosage: selectedMedication?.dosage,
        timeOfDay: timeOfDay,
        reminderTime: reminderTime,
        isActive: true,
      );

      setState(() {
        _reminders.insert(0, item);

        _medController.clear();
        _selectedMedicationValue = _customMedicationValue;
      });

      // Ask only now: the user has just told us they want to be reminded, which
      // is the moment the permission prompt actually makes sense.
      final allowed = await NotificationService.instance.requestPermissions();

      if (allowed) {
        await _syncNotification(item);
      }

      if (!mounted) return;

      // Never claim the user will be reminded when they will not be.
      _snack(
        allowed
            ? 'Reminder set for ${_formatTime(_selectedTime)} daily.'
            : 'Reminder saved, but notifications are off so it will not alert you. '
                'Enable notifications for Corvia in your device settings.',
      );
    } catch (e) {
      debugPrint('Medication reminder add failed: $e');

      if (mounted) {
        _snack(
            friendlyErrorMessage(e, whatFailed: "Couldn't add the reminder."));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  _PrescribedMedication? get _selectedPrescribedMedication {
    for (final medication in _prescribedMedications) {
      if (medication.value == _selectedMedicationValue) {
        return medication;
      }
    }

    return null;
  }

  Future<void> _toggleReminder(_MedicationReminderItem reminder) async {
    if (reminder.id.isEmpty) return;

    final newValue = !reminder.isActive;

    setState(() {
      reminder.isActive = newValue;
    });

    try {
      await SupabaseService.client.from('medication_reminders').update({
        'is_active': newValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', reminder.id);

      await _syncNotification(reminder);
    } catch (e) {
      debugPrint('Medication reminder toggle failed: $e');

      if (!mounted) return;

      setState(() {
        reminder.isActive = !newValue;
      });

      // The row did not change, so the alarm must not either.
      await _syncNotification(reminder);

      _snack("Couldn't update reminder.");
    }
  }

  Future<void> _deleteReminder(_MedicationReminderItem reminder) async {
    if (reminder.id.isEmpty) return;

    final oldIndex = _reminders.indexOf(reminder);

    setState(() {
      _reminders.remove(reminder);
    });

    try {
      await SupabaseService.client
          .from('medication_reminders')
          .delete()
          .eq('id', reminder.id);

      await NotificationService.instance.cancelMedicationReminder(reminder.id);

      _snack('Reminder deleted.');
    } catch (e) {
      debugPrint('Medication reminder delete failed: $e');

      if (!mounted) return;

      setState(() {
        if (oldIndex >= 0 && oldIndex <= _reminders.length) {
          _reminders.insert(oldIndex, reminder);
        } else {
          _reminders.add(reminder);
        }
      });

      _snack("Couldn't delete reminder.");
    }
  }

  String _databaseTime(
    TimeOfDay time,
  ) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _timeOfDayLabel(
    TimeOfDay time,
  ) {
    if (time.hour < 12) {
      return 'Morning';
    }

    if (time.hour < 17) {
      return 'Afternoon';
    }

    return 'Night';
  }

  static const List<(String, TimeOfDay)> _presetTimes = [
    ('Morning', TimeOfDay(hour: 8, minute: 0)),
    ('Midday', TimeOfDay(hour: 12, minute: 0)),
    ('Evening', TimeOfDay(hour: 18, minute: 0)),
    ('Night', TimeOfDay(hour: 21, minute: 0)),
  ];

  String _formatTime(TimeOfDay time) =>
      MaterialLocalizations.of(context).formatTimeOfDay(time);

  /// Shows a stored `HH:mm:ss` value in the user's local time format.
  String? _displayReminderTime(String? stored) {
    final parsed = NotificationService.parseReminderTime(stored);
    if (parsed == null) return stored;
    return _formatTime(TimeOfDay(hour: parsed.hour, minute: parsed.minute));
  }

  Future<void> _editReminderTime(_MedicationReminderItem reminder) async {
    if (reminder.id.isEmpty) return;

    final current = NotificationService.parseReminderTime(
      reminder.reminderTime,
    );
    final selected = await showTimePicker(
      context: context,
      initialTime: current == null
          ? _selectedTime
          : TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Change reminder time for ${reminder.medicationName}',
    );

    if (selected == null || !mounted) return;

    final oldTime = reminder.reminderTime;
    final oldLabel = reminder.timeOfDay;
    final newTime = _databaseTime(selected);
    final newLabel = _timeOfDayLabel(selected);

    setState(() {
      reminder.reminderTime = newTime;
      reminder.timeOfDay = newLabel;
    });

    try {
      await SupabaseService.client.from('medication_reminders').update({
        'reminder_time': newTime,
        'time_of_day': newLabel,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', reminder.id);

      await _syncNotification(reminder);
      _snack('Reminder moved to ${_formatTime(selected)}.');
    } catch (e) {
      debugPrint('Medication reminder time change failed: $e');
      if (!mounted) return;
      setState(() {
        reminder.reminderTime = oldTime;
        reminder.timeOfDay = oldLabel;
      });
      _snack("Couldn't change the reminder time.");
    }
  }

  Future<void> _pickReminderTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'Choose medication reminder time',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _selectedTime = selected;
    });
  }

  void _snack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (widget.embedded) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Medication schedule',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _loadReminders,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh medication reminders',
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedMedicationValue),
              initialValue: _selectedMedicationValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Medication',
                labelStyle: TextStyle(color: context.cTextSecondary),
                prefixIcon: Icon(
                  Icons.medication,
                  color: CorviaColors.accentLight,
                ),
                filled: true,
                fillColor: context.cBgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: [
                for (final medication in _prescribedMedications)
                  DropdownMenuItem<String>(
                    value: medication.value,
                    child: Text(
                      medication.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem<String>(
                  value: _customMedicationValue,
                  child: Text('Custom medication'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedMedicationValue = value;

                        if (value == _customMedicationValue) {
                          _medController.clear();
                        } else {
                          _medController.text =
                              _selectedPrescribedMedication?.name ?? '';
                        }
                      });
                    },
            ),
            if (_selectedMedicationValue == _customMedicationValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _medController,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: CorviaColors.accent,
                decoration: InputDecoration(
                  labelText: 'Custom medication name',
                  hintText: 'e.g. Vitamin D',
                  labelStyle: TextStyle(color: context.cTextSecondary),
                  hintStyle: TextStyle(color: context.cTextMuted),
                  prefixIcon: Icon(
                    Icons.edit_outlined,
                    color: CorviaColors.accentLight,
                  ),
                  filled: true,
                  fillColor: context.cBgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                textInputAction: TextInputAction.done,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Remind me at ${_formatTime(_selectedTime)}',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, time) in _presetTimes)
                  ChoiceChip(
                    label: Text('$label · ${_formatTime(time)}'),
                    selected: _selectedTime == time,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _selectedTime = time),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(
                    _presetTimes.any((preset) => preset.$2 == _selectedTime)
                        ? 'Custom time…'
                        : 'Custom · ${_formatTime(_selectedTime)}',
                  ),
                  selected: !_presetTimes.any(
                    (preset) => preset.$2 == _selectedTime,
                  ),
                  onSelected: _saving ? null : (_) => _pickReminderTime(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _addReminder,
                icon: const Icon(Icons.add_alert_rounded),
                label: const Text('Add Reminder'),
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                color: CorviaColors.accent,
              ),
            ],
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: CorviaColors.accent,
                      ),
                    )
                  : _reminders.isEmpty
                      ? Center(
                          child: Text(
                            'No medication reminders added yet.',
                            style: TextStyle(color: context.cTextSecondary),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadReminders,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _reminders.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final reminder = _reminders[index];

                              return Card(
                                color: context.cBgSecondary,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.medication,
                                    color: reminder.isActive
                                        ? CorviaColors.accentLight
                                        : context.cTextMuted,
                                  ),
                                  title: Text(
                                    reminder.medicationName,
                                    style: TextStyle(
                                      color: context.cTextPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (reminder.dosage?.trim().isNotEmpty ==
                                          true)
                                        reminder.dosage!.trim(),
                                      reminder.timeOfDay,
                                      if (reminder.reminderTime != null)
                                        _displayReminderTime(
                                          reminder.reminderTime,
                                        )!,
                                    ].join(' • '),
                                    style: TextStyle(
                                      color: context.cTextSecondary,
                                    ),
                                  ),
                                  onTap: () => _editReminderTime(reminder),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Change time',
                                        icon: const Icon(
                                          Icons.edit_calendar_outlined,
                                        ),
                                        color: context.cAccentReadable,
                                        onPressed: () =>
                                            _editReminderTime(reminder),
                                      ),
                                      Switch(
                                        value: reminder.isActive,
                                        activeThumbColor: CorviaColors.accent,
                                        onChanged: (_) =>
                                            _toggleReminder(reminder),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete reminder',
                                        icon: const Icon(Icons.delete_outline),
                                        color: Colors.redAccent,
                                        onPressed: () =>
                                            _deleteReminder(reminder),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: context.cBgPrimary,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Medication Reminders'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadReminders,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: content,
    );
  }
}

class _MedicationReminderItem {
  _MedicationReminderItem({
    required this.id,
    required this.medicationName,
    required this.dosage,
    required this.timeOfDay,
    required this.reminderTime,
    required this.isActive,
  });

  final String id;
  final String medicationName;
  final String? dosage;
  String timeOfDay;
  String? reminderTime;
  bool isActive;
}

class _PrescribedMedication {
  const _PrescribedMedication({
    required this.value,
    required this.name,
    required this.dosage,
  });

  final String value;
  final String name;
  final String? dosage;

  String get displayLabel {
    final medicationDosage = dosage?.trim();

    if (medicationDosage == null || medicationDosage.isEmpty) {
      return name;
    }

    return '$name • $medicationDosage';
  }
}
