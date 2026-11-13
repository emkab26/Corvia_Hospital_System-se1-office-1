import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';

import 'edit_request_form.dart';
import 'lab_request_form.dart';
import 'lab_result_explainer.dart';

final _log = Logger('LabResults');

class LabResultsPage extends StatefulWidget {
  const LabResultsPage({
    super.key,
  });

  @override
  State<LabResultsPage> createState() {
    return _LabResultsPageState();
  }
}

class _LabResultsPageState extends State<LabResultsPage> {
  static const Duration _requestTimeout = Duration(seconds: 20);

  final TextEditingController _searchController = TextEditingController();

  DateTimeRange? _dateRange;

  String _statusFilter = 'all';
  String _userRole = 'patient';

  bool _loadingRole = true;
  bool _loadingResults = false;

  String? _roleError;
  String? _resultsError;

  List<_LabResultRecord> _results = const [];

  @override
  void initState() {
    super.initState();

    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final role = await SupabaseService.currentUserType().timeout(
        _requestTimeout,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _userRole = _normaliseRole(
          role ?? 'patient',
        );

        _loadingRole = false;
        _roleError = null;
      });

      await _loadLabResults();
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRole = false;
        _roleError =
            'Loading your Corvia account information took too long. Please try again.';
      });
    } catch (error) {
      _log.warning(
        'Could not bootstrap lab results page: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRole = false;
        _roleError = 'Your Corvia account information could not be loaded.';
      });
    }
  }

  Future<void> _loadLabResults() async {
    if (mounted) {
      setState(() {
        _loadingResults = true;
        _resultsError = null;
      });
    }

    try {
      final patientId = await SupabaseService.currentPatientId().timeout(
        _requestTimeout,
      );

      if (patientId == null || patientId.trim().isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _results = const [];
          _loadingResults = false;
          _resultsError = 'This account is not linked to a patient record.';
        });

        return;
      }

      /*
       * The patient-facing timeline is deliberately an RPC, rather than a
       * direct table read. It exposes collection/processing progress while
       * withholding draft results, verification information, and specimen
       * identifiers until a result has been released.
       */
      final response = await SupabaseService.client
          .rpc('corvia_patient_lab_order_timeline')
          .timeout(_requestTimeout);

      final rows = _mapRows(
        response,
      );

      var results = rows
          .map(
            _LabResultRecord.fromMap,
          )
          .where(
            (result) => result.id.isNotEmpty,
          )
          .toList();

      results = await _attachDisplayNames(
        results,
      );

      results.sort(
        (
          first,
          second,
        ) {
          final firstDate = first.date ?? DateTime(1970);
          final secondDate = second.date ?? DateTime(1970);

          return secondDate.compareTo(
            firstDate,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
        _loadingResults = false;
        _resultsError = null;
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingResults = false;
        _resultsError =
            'Loading laboratory results took too long. Please check your connection and try again.';
      });
    } catch (error) {
      _log.warning(
        'Failed to load patient lab results: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingResults = false;
        _resultsError = 'Laboratory results could not be loaded. $error';
      });
    }
  }

  Future<List<_LabResultRecord>> _attachDisplayNames(
    List<_LabResultRecord> results,
  ) async {
    if (results.isEmpty) {
      return results;
    }

    final doctorIds = results
        .map(
          (result) => result.doctorId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final hospitalIds = results
        .map(
          (result) => result.hospitalId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final departmentIds = results
        .map(
          (result) => result.departmentId,
        )
        .where(
          (id) => id.isNotEmpty,
        )
        .toSet()
        .toList();

    final doctorNames = await _loadDoctorNames(
      doctorIds,
    );

    final hospitalNames = await _loadGenericNames(
      table: 'hospitals',
      ids: hospitalIds,
      nameFields: const [
        'name',
        'hospital_name',
        'title',
      ],
    );

    final departmentNames = await _loadGenericNames(
      table: 'departments',
      ids: departmentIds,
      nameFields: const [
        'name',
        'department_name',
        'title',
      ],
    );

    return results
        .map(
          (result) => result.copyWith(
            doctorName: doctorNames[result.doctorId] ?? '',
            hospitalName: hospitalNames[result.hospitalId] ?? '',
            departmentName: departmentNames[result.departmentId] ?? '',
          ),
        )
        .toList();
  }

  Future<Map<String, String>> _loadDoctorNames(
    List<String> doctorIds,
  ) async {
    if (doctorIds.isEmpty) {
      return {};
    }

    try {
      final response = await SupabaseService.client
          .from('doctors')
          .select()
          .inFilter(
            'id',
            doctorIds,
          )
          .timeout(
            _requestTimeout,
          );

      final rows = _mapRows(
        response,
      );

      final names = <String, String>{};

      for (final row in rows) {
        final id = _cleanText(
          row['id'],
        );

        if (id.isEmpty) {
          continue;
        }

        final fullName = _firstText(
          [
            row['full_name'],
            row['display_name'],
            row['name'],
          ],
          fallback: '',
        );

        if (fullName.isNotEmpty) {
          names[id] = fullName;
          continue;
        }

        final firstName = _firstText(
          [
            row['first_name'],
            row['firstname'],
            row['given_name'],
          ],
          fallback: '',
        );

        final surname = _firstText(
          [
            row['surname'],
            row['last_name'],
            row['lastname'],
            row['family_name'],
          ],
          fallback: '',
        );

        final combined = '$firstName $surname'.trim();

        if (combined.isNotEmpty) {
          names[id] = combined.startsWith('Dr') ? combined : 'Dr $combined';
        }
      }

      return names;
    } catch (error) {
      _log.warning(
        'Could not load lab-result doctor names: $error',
      );

      return {};
    }
  }

  Future<Map<String, String>> _loadGenericNames({
    required String table,
    required List<String> ids,
    required List<String> nameFields,
  }) async {
    if (ids.isEmpty) {
      return {};
    }

    try {
      final response = await SupabaseService.client
          .from(table)
          .select()
          .inFilter(
            'id',
            ids,
          )
          .timeout(
            _requestTimeout,
          );

      final rows = _mapRows(
        response,
      );

      final names = <String, String>{};

      for (final row in rows) {
        final id = _cleanText(
          row['id'],
        );

        if (id.isEmpty) {
          continue;
        }

        final name = _firstText(
          [
            for (final field in nameFields) row[field],
          ],
          fallback: '',
        );

        if (name.isNotEmpty) {
          names[id] = name;
        }
      }

      return names;
    } catch (error) {
      _log.warning(
        'Could not load $table names for lab results: $error',
      );

      return {};
    }
  }

  String _normaliseRole(
    dynamic value,
  ) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(
              '-',
              '_',
            )
            .replaceAll(
              ' ',
              '_',
            ) ??
        '';
  }

  bool get _canRequest {
    return {
      'admin',
      'hospital_admin',
      'doctor',
      'medical_doctor',
      'general_practitioner',
      'gp',
      'specialist',
      'medical_specialist',
      'specialist_doctor',
      'lab_technician',
      'laboratory_technician',
    }.contains(
      _userRole,
    );
  }

  bool get _canEditRequestForm {
    return {
      'admin',
      'hospital_admin',
      'lab_technician',
      'laboratory_technician',
    }.contains(
      _userRole,
    );
  }

  List<_LabResultRecord> get _filteredResults {
    final query = _searchController.text.trim().toLowerCase();

    final results = _results.where(
      (
        result,
      ) {
        final searchableText = [
          result.testName,
          result.status,
          result.resultText,
          result.value,
          result.unit,
          result.referenceRange,
          result.interpretation,
          result.notes,
          result.doctorName,
          result.hospitalName,
          result.departmentName,
        ].join(' ').toLowerCase();

        final matchesSearch = query.isEmpty || searchableText.contains(query);

        final matchesStatus =
            _statusFilter == 'all' || result.status == _statusFilter;

        final matchesDate = _dateRange == null ||
            result.date == null ||
            (!_dateOnly(
                  result.date!,
                ).isBefore(
                  _dateOnly(
                    _dateRange!.start,
                  ),
                ) &&
                !_dateOnly(
                  result.date!,
                ).isAfter(
                  _dateOnly(
                    _dateRange!.end,
                  ),
                ));

        return matchesSearch && matchesStatus && matchesDate;
      },
    ).toList();

    results.sort(
      (
        first,
        second,
      ) {
        final firstDate = first.date ?? DateTime(1970);
        final secondDate = second.date ?? DateTime(1970);

        return secondDate.compareTo(
          firstDate,
        );
      },
    );

    return results;
  }

  DateTime _dateOnly(
    DateTime value,
  ) {
    return DateTime(
      value.year,
      value.month,
      value.day,
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(
        now.year - 10,
      ),
      lastDate: DateTime(
        now.year + 1,
      ),
      initialDateRange: _dateRange,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _dateRange = picked;
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _statusFilter = 'all';
      _dateRange = null;
    });
  }

  Future<void> _openFile(
    _LabResultRecord result,
  ) async {
    final url = result.fileUrl.trim();

    if (url.isEmpty) {
      _showMessage(
        'No result document is attached to this laboratory result.',
      );

      return;
    }

    try {
      final launched = await launchUrlString(
        url,
      );

      if (!launched) {
        _showMessage(
          'The laboratory result document could not be opened.',
        );
      }
    } catch (error) {
      _showMessage(
        'The laboratory result document could not be opened. $error',
      );
    }
  }

  Future<void> _shareFile(
    _LabResultRecord result,
  ) async {
    final url = result.fileUrl.trim();

    if (url.isEmpty) {
      _showMessage(
        'No PDF document is attached to this laboratory result.',
      );

      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              url,
            ),
          )
          .timeout(
            _requestTimeout,
          );

      if (response.statusCode != 200) {
        _showMessage(
          'The result document could not be downloaded.',
        );

        return;
      }

      await Printing.sharePdf(
        bytes: response.bodyBytes,
        filename: '${_safeFileName(result.testName)}.pdf',
      );
    } catch (error) {
      _log.warning(
        'Lab result export error: $error',
      );

      _showMessage(
        'The result document could not be exported.',
      );
    }
  }

  String _safeFileName(
    String value,
  ) {
    final cleaned = value
        .trim()
        .replaceAll(
          RegExp(
            r'[^A-Za-z0-9_-]+',
          ),
          '_',
        )
        .replaceAll(
          RegExp(
            r'_+',
          ),
          '_',
        );

    if (cleaned.isEmpty) {
      return 'Corvia_Lab_Result';
    }

    return cleaned;
  }

  void _openExplainer(
    _LabResultRecord result,
  ) {
    if (!result.hasExplainableData) {
      _showMessage(
        'There is not enough result information to explain yet.',
      );

      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (
          context,
        ) {
          return LabResultExplainerPage(
            labResultId: result.id,
            testName: result.testName,
            initialText: result.explanationText,
          );
        },
      ),
    );
  }

  Future<void> _openRequestForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (
          context,
        ) {
          return const LabRequestForm();
        },
      ),
    );

    if (mounted) {
      await _loadLabResults();
    }
  }

  Future<void> _openEditForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (
          context,
        ) {
          return const EditRequestForm();
        },
      ),
    );
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
    if (_loadingRole) {
      return Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(
          title: const Text(
            'Lab Results',
          ),
        ),
        body: StatusView.loading(
          message: 'Loading your laboratory information...',
        ),
      );
    }

    if (_roleError != null) {
      return Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(
          title: const Text(
            'Lab Results',
          ),
        ),
        body: StatusView.error(
          friendlyMessage: _roleError!,
          onRetry: () {
            setState(() {
              _loadingRole = true;
              _roleError = null;
            });

            _bootstrap();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Lab Results',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingResults ? null : _loadLabResults,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLabResults,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(
            16,
          ),
          children: [
            _buildHeader(),
            if (_canRequest || _canEditRequestForm) ...[
              const SizedBox(
                height: 16,
              ),
              _buildStaffActions(),
            ],
            const SizedBox(
              height: 18,
            ),
            _buildFilters(),
            const SizedBox(
              height: 18,
            ),
            _buildResultsSection(),
            const SizedBox(
              height: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final total = _results.length;
    final released = _results
        .where(
          (result) => result.status == 'released',
        )
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        gradient: context.cBgGradient,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(
                15,
              ),
            ),
            child: const Icon(
              Icons.biotech,
              color: Colors.blueAccent,
              size: 29,
            ),
          ),
          const SizedBox(
            width: 14,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Laboratory Results',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  total == 0
                      ? 'Track requested tests and view results once your laboratory has released them.'
                      : '$total laboratory order${total == 1 ? '' : 's'} · $released released result${released == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffActions() {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final narrow = constraints.maxWidth < 620;

        final actions = <Widget>[];

        if (_canRequest) {
          actions.add(
            _ActionCard(
              icon: Icons.add_circle_outline,
              title: 'Request Lab Test',
              subtitle: 'Create a laboratory test request',
              onTap: _openRequestForm,
            ),
          );
        }

        if (_canEditRequestForm) {
          actions.add(
            _ActionCard(
              icon: Icons.edit_note_outlined,
              title: 'Edit Request Form',
              subtitle: 'Manage the laboratory request template',
              onTap: _openEditForm,
            ),
          );
        }

        if (narrow || actions.length == 1) {
          return Column(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                actions[index],
                if (index != actions.length - 1)
                  const SizedBox(
                    height: 10,
                  ),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              Expanded(
                child: actions[index],
              ),
              if (index != actions.length - 1)
                const SizedBox(
                  width: 12,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (
            value,
          ) {
            setState(() {});
          },
          style: TextStyle(
            color: context.cTextPrimary,
          ),
          decoration: InputDecoration(
            labelText: 'Search lab results',
            hintText: 'Test, result, doctor, hospital, status or notes',
            prefixIcon: const Icon(
              Icons.search,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      setState(
                        () {
                          _searchController.clear();
                        },
                      );
                    },
                    icon: const Icon(
                      Icons.clear,
                    ),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: context.cBgSecondary,
              style: TextStyle(
                color: context.cTextPrimary,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'all',
                  child: Text(
                    'All statuses',
                  ),
                ),
                DropdownMenuItem(
                  value: 'requested',
                  child: Text(
                    'Requested',
                  ),
                ),
                DropdownMenuItem(
                  value: 'collected',
                  child: Text(
                    'Sample Collected',
                  ),
                ),
                DropdownMenuItem(
                  value: 'processing',
                  child: Text(
                    'Processing',
                  ),
                ),
                DropdownMenuItem(
                  value: 'released',
                  child: Text(
                    'Released',
                  ),
                ),
                DropdownMenuItem(
                  value: 'cancelled',
                  child: Text(
                    'Cancelled',
                  ),
                ),
              ],
              onChanged: (
                value,
              ) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _statusFilter = value;
                });
              },
            ),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(
                Icons.date_range,
              ),
              label: Text(
                _dateRange == null
                    ? 'Date range'
                    : '${_formatShortDate(_dateRange!.start)}'
                        ' - '
                        '${_formatShortDate(_dateRange!.end)}',
              ),
            ),
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(
                Icons.filter_alt_off,
              ),
              label: const Text(
                'Clear filters',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultsSection() {
    if (_loadingResults) {
      return StatusView.loading(
        message: 'Loading laboratory results...',
      );
    }

    if (_resultsError != null) {
      return StatusView.error(
        friendlyMessage: _resultsError!,
        onRetry: _loadLabResults,
      );
    }

    if (_results.isEmpty) {
      return StatusView.empty(
        icon: Icons.biotech_outlined,
        title: 'No lab results found',
        subtitle: 'No laboratory results have been linked to this patient yet.',
        onRetry: _loadLabResults,
      );
    }

    final results = _filteredResults;

    if (results.isEmpty) {
      return StatusView.empty(
        icon: Icons.search_off_rounded,
        title: 'No matching results',
        subtitle: 'Try changing your search or filters.',
        onRetry: () {
          _clearFilters();
        },
        retryLabel: 'Clear filters',
      );
    }

    return Column(
      children: [
        for (var index = 0; index < results.length; index++) ...[
          _buildResultCard(
            results[index],
          ),
          if (index != results.length - 1)
            const SizedBox(
              height: 12,
            ),
        ],
      ],
    );
  }

  Widget _buildResultCard(
    _LabResultRecord result,
  ) {
    final statusColor = _statusColor(
      result.status,
    );

    final hasDocument = result.fileUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: statusColor.withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  result.status == 'released'
                      ? Icons.science_rounded
                      : Icons.hourglass_top_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.testName,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      result.date == null
                          ? 'Date unavailable'
                          : _formatDateTime(
                              result.date!,
                            ),
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              _StatusPill(
                label: _prettyStatus(
                  result.status,
                ),
                color: statusColor,
              ),
            ],
          ),
          if (result.doctorName.isNotEmpty ||
              result.hospitalName.isNotEmpty ||
              result.departmentName.isNotEmpty) ...[
            const SizedBox(
              height: 12,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (result.doctorName.isNotEmpty)
                  _MetaChip(
                    icon: Icons.person_outline_rounded,
                    label: result.doctorName,
                  ),
                if (result.hospitalName.isNotEmpty)
                  _MetaChip(
                    icon: Icons.local_hospital_outlined,
                    label: result.hospitalName,
                  ),
                if (result.departmentName.isNotEmpty)
                  _MetaChip(
                    icon: Icons.domain_rounded,
                    label: result.departmentName,
                  ),
              ],
            ),
          ],
          const SizedBox(
            height: 13,
          ),
          if (result.hasResultData)
            _ResultSummaryBox(
              result: result,
            )
          else
            _NoticeBox(
              icon: hasDocument
                  ? Icons.description_outlined
                  : Icons.info_outline_rounded,
              color: result.status == 'released'
                  ? Colors.orangeAccent
                  : Colors.blueAccent,
              title: hasDocument
                  ? 'Document attached'
                  : result.status == 'released'
                      ? 'Result details not attached yet'
                      : result.status == 'collected'
                          ? 'Sample collected'
                          : result.status == 'processing'
                              ? 'Sample being processed'
                              : result.status == 'requested'
                                  ? 'Test requested'
                                  : result.status == 'cancelled'
                                      ? 'Test cancelled'
                                      : 'Result still pending',
              message: hasDocument
                  ? 'This lab result has a document attached, but no structured result text was provided.'
                  : result.status == 'released'
                      ? 'This result has been released, but no result text or PDF document is attached yet.'
                      : result.status == 'collected'
                          ? 'Your sample has been collected and is being sent to the laboratory.'
                          : result.status == 'processing'
                              ? 'The laboratory is processing your sample. Your result will appear here once it has been released to you.'
                              : result.status == 'cancelled'
                                  ? 'This laboratory test is no longer active. Contact your care team if you expected it to continue.'
                                  : 'Your doctor has requested this test. Go to the '
                                      '${result.hospitalName.isNotEmpty ? '${result.hospitalName} ' : 'hospital '}'
                                      'laboratory collection point with your ID to give your sample, '
                                      'or a nurse will take it if you are admitted. '
                                      'Your result will appear here once it is released.',
            ),
          const SizedBox(
            height: 14,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (result.hasExplainableData)
                FilledButton.icon(
                  onPressed: () {
                    _openExplainer(
                      result,
                    );
                  },
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 18,
                  ),
                  label: const Text(
                    'Explain Result',
                  ),
                ),
              if (hasDocument)
                OutlinedButton.icon(
                  onPressed: () {
                    _openFile(
                      result,
                    );
                  },
                  icon: const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'Open Document',
                  ),
                ),
              if (hasDocument)
                OutlinedButton.icon(
                  onPressed: () {
                    _shareFile(
                      result,
                    );
                  },
                  icon: const Icon(
                    Icons.share_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'Share',
                  ),
                ),
              if (!result.hasExplainableData && !hasDocument)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(
                    Icons.pending_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'Awaiting Result',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(
    String status,
  ) {
    switch (status) {
      case 'released':
        return Colors.green;

      case 'processing':
        return Colors.amber.shade700;

      case 'collected':
        return Colors.blue.shade700;

      case 'requested':
        return Colors.orange.shade700;

      case 'cancelled':
      case 'rejected':
        return CorviaColors.danger;

      default:
        return Colors.blueAccent;
    }
  }

  String _prettyStatus(
    String status,
  ) {
    switch (status) {
      case 'requested':
        return 'Requested';
      case 'collected':
        return 'Sample Collected';
      case 'processing':
        return 'Processing';
      case 'released':
        return 'Released';
      case 'cancelled':
        return 'Cancelled';
    }

    final cleaned = status
        .trim()
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        );

    if (cleaned.isEmpty) {
      return 'Unknown';
    }

    return cleaned
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (
            word,
          ) =>
              word.isNotEmpty,
        )
        .map(
          (
            word,
          ) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(
          ' ',
        );
  }

  String _formatShortDate(
    DateTime date,
  ) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateTime(
    DateTime date,
  ) {
    final local = date.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;

  final String title;
  final String subtitle;

  final VoidCallback onTap;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color: context.cBgSecondary,
      borderRadius: BorderRadius.circular(
        15,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          15,
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: 105,
          ),
          padding: const EdgeInsets.all(
            16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              15,
            ),
            border: Border.all(
              color: Colors.blueAccent.withValues(
                alpha: 0.30,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(
                    alpha: 0.13,
                  ),
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                ),
                child: Icon(
                  icon,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(
                width: 13,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.cTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.13,
        ),
        borderRadius: BorderRadius.circular(
          99,
        ),
        border: Border.all(
          color: color,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          99,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            width: 6,
          ),
          Text(
            label,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSummaryBox extends StatelessWidget {
  const _ResultSummaryBox({
    required this.result,
  });

  final _LabResultRecord result;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Result Details',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          if (result.resultText.isNotEmpty)
            _ResultLine(
              label: 'Result',
              value: result.resultText,
            ),
          if (result.value.isNotEmpty)
            _ResultLine(
              label: 'Value',
              value: result.unit.isEmpty
                  ? result.value
                  : '${result.value} ${result.unit}',
            ),
          if (result.referenceRange.isNotEmpty)
            _ResultLine(
              label: 'Reference Range',
              value: result.referenceRange,
            ),
          if (result.interpretation.isNotEmpty)
            _ResultLine(
              label: 'Interpretation',
              value: result.interpretation,
            ),
          if (result.notes.isNotEmpty)
            _ResultLine(
              label: 'Notes',
              value: result.notes,
            ),
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.09,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  message,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12.5,
                    height: 1.4,
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

class _LabResultRecord {
  const _LabResultRecord({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.hospitalId,
    required this.departmentId,
    required this.doctorName,
    required this.hospitalName,
    required this.departmentName,
    required this.testName,
    required this.status,
    required this.date,
    required this.fileUrl,
    required this.resultText,
    required this.value,
    required this.unit,
    required this.referenceRange,
    required this.interpretation,
    required this.notes,
    required this.explanationText,
    required this.hasExplainableData,
  });

  final String id;
  final String patientId;

  final String doctorId;
  final String hospitalId;
  final String departmentId;

  final String doctorName;
  final String hospitalName;
  final String departmentName;

  final String testName;
  final String status;

  final DateTime? date;

  final String fileUrl;

  final String resultText;
  final String value;
  final String unit;
  final String referenceRange;
  final String interpretation;
  final String notes;

  final String explanationText;

  final bool hasExplainableData;

  bool get hasResultData {
    return resultText.isNotEmpty ||
        value.isNotEmpty ||
        referenceRange.isNotEmpty ||
        interpretation.isNotEmpty ||
        notes.isNotEmpty;
  }

  _LabResultRecord copyWith({
    String? doctorName,
    String? hospitalName,
    String? departmentName,
  }) {
    return _LabResultRecord(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      hospitalId: hospitalId,
      departmentId: departmentId,
      doctorName: doctorName ?? this.doctorName,
      hospitalName: hospitalName ?? this.hospitalName,
      departmentName: departmentName ?? this.departmentName,
      testName: testName,
      status: status,
      date: date,
      fileUrl: fileUrl,
      resultText: resultText,
      value: value,
      unit: unit,
      referenceRange: referenceRange,
      interpretation: interpretation,
      notes: notes,
      explanationText: explanationText,
      hasExplainableData: hasExplainableData,
    );
  }

  factory _LabResultRecord.fromMap(
    Map<String, dynamic> map,
  ) {
    final testName = _firstText(
      [
        map['test_name'],
        map['name'],
        map['title'],
        map['test'],
      ],
      fallback: 'Laboratory Test',
    );

    final status = _normaliseStatus(
      _firstText(
        [
          map['status'],
        ],
        fallback: 'pending',
      ),
    );

    final date = _firstDate(
      map,
      const [
        'result_date',
        'completed_at',
        'reviewed_at',
        'updated_at',
        'created_at',
      ],
    );

    final fileUrl = _firstText(
      [
        map['file_url'],
        map['result_url'],
        map['pdf_url'],
        map['document_url'],
        map['attachment_url'],
      ],
      fallback: '',
    );

    final resultText = _valueText(
      map['result_text'] ?? map['result'] ?? map['results'],
    );

    final value = _valueText(
      map['value'] ?? map['result_value'],
    );

    final unit = _firstText(
      [
        map['unit'],
        map['units'],
      ],
      fallback: '',
    );

    final referenceRange = _firstText(
      [
        map['reference_range'],
        map['normal_range'],
        map['range'],
      ],
      fallback: '',
    );

    final interpretation = _firstText(
      [
        map['interpretation'],
        map['clinical_interpretation'],
      ],
      fallback: '',
    );

    final notes = _firstText(
      [
        map['notes'],
        map['comments'],
        map['comment'],
      ],
      fallback: '',
    );

    final patientCanViewResult = status == 'released';
    final visibleFileUrl = patientCanViewResult ? fileUrl : '';
    final visibleResultText = patientCanViewResult ? resultText : '';
    final visibleValue = patientCanViewResult ? value : '';
    final visibleUnit = patientCanViewResult ? unit : '';
    final visibleReferenceRange = patientCanViewResult ? referenceRange : '';
    final visibleInterpretation = patientCanViewResult ? interpretation : '';
    final visibleNotes = patientCanViewResult ? notes : '';

    final explainableLines = <String>[
      'Test: $testName',
      'Status: ${_prettyStaticStatus(status)}',
    ];

    if (visibleResultText.isNotEmpty) {
      explainableLines.add(
        'Result: $visibleResultText',
      );
    }

    if (visibleValue.isNotEmpty) {
      explainableLines.add(
        visibleUnit.isEmpty
            ? 'Value: $visibleValue'
            : 'Value: $visibleValue $visibleUnit',
      );
    }

    if (visibleReferenceRange.isNotEmpty) {
      explainableLines.add(
        'Reference range: $visibleReferenceRange',
      );
    }

    if (visibleInterpretation.isNotEmpty) {
      explainableLines.add(
        'Interpretation: $visibleInterpretation',
      );
    }

    if (visibleNotes.isNotEmpty) {
      explainableLines.add(
        'Notes: $visibleNotes',
      );
    }

    if (date != null) {
      explainableLines.add(
        'Result date: ${date.toLocal()}',
      );
    }

    final hasClinicalData = visibleResultText.isNotEmpty ||
        visibleValue.isNotEmpty ||
        visibleReferenceRange.isNotEmpty ||
        visibleInterpretation.isNotEmpty ||
        visibleNotes.isNotEmpty;

    return _LabResultRecord(
      id: _cleanText(
        map['id'],
      ),
      patientId: _cleanText(
        map['patient_id'],
      ),
      doctorId: _cleanText(
        map['doctor_id'],
      ),
      hospitalId: _cleanText(
        map['hospital_id'],
      ),
      departmentId: _cleanText(
        map['department_id'],
      ),
      doctorName: '',
      hospitalName: '',
      departmentName: '',
      testName: testName,
      status: status,
      date: date,
      fileUrl: visibleFileUrl,
      resultText: visibleResultText,
      value: visibleValue,
      unit: visibleUnit,
      referenceRange: visibleReferenceRange,
      interpretation: visibleInterpretation,
      notes: visibleNotes,
      explanationText: explainableLines.join(
        '\n',
      ),
      hasExplainableData: hasClinicalData,
    );
  }

  static String _normaliseStatus(
    String value,
  ) {
    final status = value
        .trim()
        .toLowerCase()
        .replaceAll(
          '-',
          '_',
        )
        .replaceAll(
          ' ',
          '_',
        );

    const released = {
      'released',
      'completed',
      'complete',
      'done',
      'finalized',
      'finalised',
      'finished',
      'reviewed',
    };

    const collected = {
      'collected',
      'sample_collected',
    };

    if (collected.contains(status)) {
      return 'collected';
    }

    const processing = {
      'processing',
      'in_progress',
      'started',
      'collecting',
      'sent',
      'received',
      'awaiting_verification',
      'awaiting_doctor_review',
    };

    const cancelled = {
      'cancelled',
      'canceled',
      'rejected',
      'void',
    };

    if (released.contains(
      status,
    )) {
      return 'released';
    }

    if (processing.contains(
      status,
    )) {
      return 'processing';
    }

    if (cancelled.contains(
      status,
    )) {
      return 'cancelled';
    }

    if (status.isEmpty) {
      return 'requested';
    }

    const requested = {
      'pending',
      'requested',
      'ordered',
      'awaiting',
      'scheduled',
    };

    if (requested.contains(status)) {
      return 'requested';
    }

    return status;
  }

  static String _prettyStaticStatus(
    String value,
  ) {
    return value
        .replaceAll(
          '_',
          ' ',
        )
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (
            word,
          ) =>
              word.isNotEmpty,
        )
        .map(
          (
            word,
          ) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(
          ' ',
        );
  }

  static String _valueText(
    dynamic value,
  ) {
    if (value == null) {
      return '';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent(
          '  ',
        ).convert(
          value,
        );
      } catch (_) {
        return value.toString();
      }
    }

    return value.toString().trim();
  }

  static String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = _cleanText(
        value,
      );

      if (text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  static DateTime? _firstDate(
    Map<String, dynamic> map,
    List<String> columns,
  ) {
    for (final column in columns) {
      final raw = map[column];

      if (raw == null) {
        continue;
      }

      final parsed = DateTime.tryParse(
        raw.toString(),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }
}

String _cleanText(
  dynamic value,
) {
  if (value == null) {
    return '';
  }

  final text = value.toString().trim();

  if (text.isEmpty || text.toLowerCase() == 'null') {
    return '';
  }

  return text;
}

String _firstText(
  List<dynamic> values, {
  required String fallback,
}) {
  for (final value in values) {
    final text = _cleanText(
      value,
    );

    if (text.isNotEmpty) {
      return text;
    }
  }

  return fallback;
}

List<Map<String, dynamic>> _mapRows(
  dynamic response,
) {
  if (response is! List) {
    return [];
  }

  return response
      .whereType<Map>()
      .map(
        (
          row,
        ) =>
            Map<String, dynamic>.from(
          row,
        ),
      )
      .toList();
}
