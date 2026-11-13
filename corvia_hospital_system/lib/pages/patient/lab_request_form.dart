import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/lab_catalog_service.dart';
import '../../services/supabase_service.dart';

final SupabaseClient _supabase = Supabase.instance.client;

class LabRequestForm extends StatefulWidget {
  const LabRequestForm({
    super.key,
  });

  @override
  State<LabRequestForm> createState() {
    return _LabRequestFormState();
  }
}

class _LabRequestFormState extends State<LabRequestForm> {
  List<LabCatalogGroup> _groups = const [];

  List<List<bool>> _checkedTests = [];

  bool _isLoadingCatalog = true;
  bool _profileLoaded = false;
  bool _isSubmitting = false;

  String? _loadError;
  String? _submitError;

  String _firstName = '';
  String _surname = '';
  String _dateOfBirth = '';

  @override
  void initState() {
    super.initState();

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadCatalog(),
      _loadProfile(),
    ]);
  }

  Future<void> _loadCatalog() async {
    try {
      final groups = await LabCatalogService.loadCatalog();

      if (!mounted) {
        return;
      }

      setState(() {
        _groups = groups;

        _checkedTests = groups
            .map(
              (group) => List<bool>.filled(
                group.tests.length,
                false,
              ),
            )
            .toList();

        _isLoadingCatalog = false;
        _loadError = null;
      });
    } catch (error) {
      debugPrint(
        'Lab catalogue loading error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _groups = const [];
        _checkedTests = [];
        _isLoadingCatalog = false;
        _loadError =
            'The laboratory test list could not be loaded. Please try again.';
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final patientId = await SupabaseService.currentPatientId();

      if (patientId == null || patientId.trim().isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _profileLoaded = true;
        });

        return;
      }

      final row = await _supabase
          .from('patients')
          .select(
            'date_of_birth, '
            'profile:profiles!patients_profile_id_fkey('
            'first_name, surname'
            ')',
          )
          .eq(
            'id',
            patientId,
          )
          .maybeSingle();

      if (!mounted) {
        return;
      }

      final rawProfile = row?['profile'];

      final profile = rawProfile is Map
          ? Map<String, dynamic>.from(
              rawProfile,
            )
          : <String, dynamic>{};

      setState(() {
        _firstName = profile['first_name']?.toString().trim() ?? '';

        _surname = profile['surname']?.toString().trim() ?? '';

        _dateOfBirth = row?['date_of_birth']?.toString().trim() ?? '';

        _profileLoaded = true;
      });
    } catch (error) {
      debugPrint(
        'Lab request patient profile loading error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profileLoaded = true;
      });
    }
  }

  List<_SelectedLabTest> get _selectedTests {
    final selected = <_SelectedLabTest>[];

    for (var groupIndex = 0;
        groupIndex < _groups.length;
        groupIndex++) {
      final group = _groups[groupIndex];

      for (var testIndex = 0;
          testIndex < group.tests.length;
          testIndex++) {
        if (!_checkedTests[groupIndex][testIndex]) {
          continue;
        }

        final test = group.tests[testIndex];

        selected.add(
          _SelectedLabTest(
            name: test.name,
            description: test.description,
            price: test.price,
          ),
        );
      }
    }

    return selected;
  }

  num get _total {
    return _selectedTests.fold<num>(
      0,
      (sum, test) => sum + test.price,
    );
  }

  String get _fileName {
    final first = _safeFilePart(
      _firstName.isEmpty ? 'Patient' : _firstName,
    );

    final surname = _safeFilePart(
      _surname.isEmpty ? 'Lab_Request' : _surname,
    );

    return '${first}_${surname}_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf';
  }

  String _safeFilePart(
    String value,
  ) {
    return value
        .trim()
        .replaceAll(
          RegExp(r'[^A-Za-z0-9_-]+'),
          '_',
        )
        .replaceAll(
          RegExp(r'_+'),
          '_',
        );
  }

  Future<String> _createAndUploadPdf(
    List<_SelectedLabTest> selected,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(
          32,
        ),
        build: (
          context,
        ) {
          return [
            pw.Text(
              'Corvia Medical',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(
              height: 8,
            ),
            pw.Text(
              'Laboratory Test Request',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(
              height: 20,
            ),
            pw.Text(
              'Patient: ${[
                _firstName,
                _surname,
              ].where((value) => value.trim().isNotEmpty).join(' ')}',
            ),
            pw.Text(
              'Date of birth: '
              '${_dateOfBirth.isEmpty ? 'Not available' : _dateOfBirth}',
            ),
            pw.Text(
              'Generated: ${DateTime.now().toLocal()}',
            ),
            pw.SizedBox(
              height: 20,
            ),
            pw.Text(
              'Requested tests',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(
              height: 8,
            ),
            ...selected.map(
              (test) {
                return pw.Container(
                  margin: const pw.EdgeInsets.only(
                    bottom: 7,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${test.name} - R${test.price}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (test.description.trim().isNotEmpty)
                        pw.Text(
                          test.description,
                        ),
                    ],
                  ),
                );
              },
            ),
            pw.Divider(),
            pw.Text(
              'Total: R$_total',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();

    final fileName = _fileName;

    await _supabase.storage
        .from('TestRequestforms')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: false,
          ),
        );

    return fileName;
  }

  Future<void> _openConfirmation() async {
    if (_isSubmitting) {
      return;
    }

    final selected = _selectedTests;

    if (selected.isEmpty) {
      _showMessage(
        'Select at least one laboratory test.',
      );

      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Confirm laboratory tests',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 520,
              maxHeight: 420,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: selected.length,
                    separatorBuilder: (
                      context,
                      index,
                    ) {
                      return const Divider();
                    },
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      final test = selected[index];

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          test.name,
                        ),
                        subtitle: test.description.isEmpty
                            ? null
                            : Text(
                                test.description,
                              ),
                        trailing: Text(
                          'R${test.price}',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'Total: R$_total',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              child: const Text(
                'Confirm',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _submit(
      selected,
    );
  }

  Future<void> _submit(
    List<_SelectedLabTest> selected,
  ) async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await _createAndUploadPdf(
        selected,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Laboratory request form submitted successfully.',
      );

      setState(() {
        for (var groupIndex = 0;
            groupIndex < _checkedTests.length;
            groupIndex++) {
          for (var testIndex = 0;
              testIndex < _checkedTests[groupIndex].length;
              testIndex++) {
            _checkedTests[groupIndex][testIndex] = false;
          }
        }
      });
    } catch (error) {
      debugPrint(
        'Lab request submission error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _submitError =
            'The laboratory request could not be submitted. $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Laboratory Test Request',
        ),
      ),
      body: _isLoadingCatalog
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _loadError != null
              ? _buildLoadError()
              : RefreshIndicator(
                  onRefresh: _loadCatalog,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(
                      16,
                    ),
                    children: [
                      _buildPatientCard(),
                      const SizedBox(
                        height: 18,
                      ),
                      ...List.generate(
                        _groups.length,
                        (
                          groupIndex,
                        ) {
                          return _buildGroup(
                            groupIndex,
                          );
                        },
                      ),
                      if (_submitError != null) ...[
                        const SizedBox(
                          height: 12,
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                            border: Border.all(
                              color: Colors.redAccent.withValues(
                                alpha: 0.40,
                              ),
                            ),
                          ),
                          child: Text(
                            _submitError!,
                          ),
                        ),
                      ],
                      const SizedBox(
                        height: 18,
                      ),
                      LayoutBuilder(
                        builder: (
                          context,
                          constraints,
                        ) {
                          final buttonWidth = constraints.maxWidth > 600
                              ? 360.0
                              : constraints.maxWidth;

                          return Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: buttonWidth,
                              child: FilledButton.icon(
                                onPressed:
                                    _isSubmitting ? null : _openConfirmation,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send_outlined,
                                      ),
                                label: Text(
                                  _isSubmitting
                                      ? 'Submitting...'
                                      : 'Submit Request',
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(
                        height: 30,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 54,
              color: Colors.redAccent,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 16,
            ),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _isLoadingCatalog = true;
                  _loadError = null;
                });

                _loadCatalog();
              },
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: _profileLoaded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                      ),
                      SizedBox(
                        width: 8,
                      ),
                      Text(
                        'Patient',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  Text(
                    'Name: '
                    '${_firstName.isEmpty ? 'Not available' : _firstName}',
                  ),
                  Text(
                    'Surname: '
                    '${_surname.isEmpty ? 'Not available' : _surname}',
                  ),
                  Text(
                    'Date of birth: '
                    '${_dateOfBirth.isEmpty ? 'Not available' : _dateOfBirth}',
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(),
              ),
      ),
    );
  }

  Widget _buildGroup(
    int groupIndex,
  ) {
    final group = _groups[groupIndex];

    return Card(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                10,
                16,
                8,
              ),
              child: Text(
                group.heading,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...List.generate(
              group.tests.length,
              (
                testIndex,
              ) {
                final test = group.tests[testIndex];

                return CheckboxListTile(
                  value: _checkedTests[groupIndex][testIndex],
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    test.name,
                  ),
                  subtitle: test.description.isEmpty
                      ? Text(
                          'R${test.price}',
                        )
                      : Text(
                          '${test.description}\nR${test.price}',
                        ),
                  isThreeLine: test.description.isNotEmpty,
                  onChanged: _isSubmitting
                      ? null
                      : (
                          value,
                        ) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _checkedTests[groupIndex][testIndex] = value;
                          });
                        },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedLabTest {
  const _SelectedLabTest({
    required this.name,
    required this.description,
    required this.price,
  });

  final String name;
  final String description;
  final num price;
}