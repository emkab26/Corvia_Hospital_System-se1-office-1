import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'hospital_form_pdf_preview_page.dart';

class PatientReleasedFormsPage extends StatefulWidget {
  const PatientReleasedFormsPage({
    super.key,
  });

  @override
  State<PatientReleasedFormsPage> createState() =>
      _PatientReleasedFormsPageState();
}

class _PatientReleasedFormsPageState extends State<PatientReleasedFormsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;

  String? _errorMessage;
  String? _patientId;

  String _selectedFilter = 'All';

  List<_ReleasedFormRecord> _forms = [];

  static const List<String> _filters = [
    'All',
    'Admission',
    'Emergency',
    'Nursing',
    'Medication',
    'Pharmacy',
    'Laboratory',
    'Imaging',
    'Discharge',
    'Transfer',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    _loadReleasedForms();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadReleasedForms() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final patientId = await _resolveCurrentPatientId();

      if (patientId == null || patientId.trim().isEmpty) {
        throw Exception(
          'No patient record is linked to this Corvia account.',
        );
      }

      _patientId = patientId;

      final response =
          await _supabase.from('hospital_form_instances').select().eq(
                'patient_id',
                patientId,
              );

      final instances = _rows(response)
          .where(
            _isReleasedInstance,
          )
          .toList();

      final templateIds = instances
          .map(
            (instance) => _cleanId(
              instance['template_id'],
            ),
          )
          .whereType<String>()
          .toSet();

      final versionIds = instances
          .map(
            (instance) => _cleanId(
              instance['template_version_id'],
            ),
          )
          .whereType<String>()
          .toSet();

      final templates = await _loadTemplates(
        templateIds,
      );

      final versions = await _loadTemplateVersions(
        versionIds,
      );

      final records = <_ReleasedFormRecord>[];

      for (final instance in instances) {
        final instanceId = _cleanId(
          instance['id'],
        );

        if (instanceId == null) {
          continue;
        }

        final templateId = _cleanId(
          instance['template_id'],
        );

        final versionId = _cleanId(
          instance['template_version_id'],
        );

        final template = templateId == null ? null : templates[templateId];

        final version = versionId == null ? null : versions[versionId];

        final title = _firstText(
          [
            template?['display_name'],
            template?['title'],
            template?['name'],
            template?['template_name'],
            template?['code'],
            template?['slug'],
            instance['title'],
            instance['form_name'],
          ],
          fallback: 'Hospital Form',
        );

        final code = _firstText(
          [
            template?['code'],
            template?['slug'],
            template?['template_code'],
          ],
          fallback: '',
        );

        final category = _normaliseCategory(
          _firstText(
            [
              template?['category'],
              template?['document_category'],
              template?['form_category'],
              instance['category'],
              code,
              title,
            ],
            fallback: 'other',
          ),
        );

        final description = _firstText(
          [
            template?['description'],
            template?['summary'],
            version?['description'],
          ],
          fallback: 'Released hospital document.',
        );

        final hospitalId = _cleanId(
          instance['hospital_id'],
        );

        final hospitalName = await _resolveHospitalName(
          hospitalId,
        );

        records.add(
          _ReleasedFormRecord(
            instanceId: instanceId,
            patientId: patientId,
            hospitalId: hospitalId,
            admissionId: _cleanId(
              instance['admission_id'],
            ),
            templateId: templateId,
            templateVersionId: versionId,
            title: title,
            code: code,
            category: category,
            description: description,
            status: _firstText(
              [
                instance['status'],
              ],
              fallback: 'finalized',
            ),
            hospitalName: hospitalName,
            finalizedAt: _firstDate(
              instance,
              const [
                'finalized_at',
                'completed_at',
                'submitted_at',
                'updated_at',
                'created_at',
              ],
            ),
            releasedAt: _firstDate(
              instance,
              const [
                'released_to_patient_at',
                'patient_released_at',
                'released_at',
                'updated_at',
              ],
            ),
            rawInstance: instance,
            rawTemplate: template,
            rawVersion: version,
          ),
        );
      }

      records.sort(
        (
          first,
          second,
        ) {
          final firstDate =
              first.releasedAt ?? first.finalizedAt ?? DateTime(1970);

          final secondDate =
              second.releasedAt ?? second.finalizedAt ?? DateTime(1970);

          return secondDate.compareTo(
            firstDate,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _forms = records;
        _loading = false;
      });
    } catch (error) {
      debugPrint(
        'Patient Released Forms load error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _forms = [];
        _loading = false;
        _errorMessage = _cleanError(error);
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
    });

    try {
      await _loadReleasedForms();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<String?> _resolveCurrentPatientId() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No signed-in Corvia account was found.',
      );
    }

    Map<String, dynamic>? profile;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq(
            'user_id',
            user.id,
          )
          .maybeSingle();

      if (response != null) {
        profile = Map<String, dynamic>.from(
          response,
        );
      }
    } catch (error) {
      debugPrint(
        'Released Forms profile lookup failed: $error',
      );
    }

    final profileId = _cleanId(
      profile?['id'],
    );

    final identifiers = <String>{
      user.id,
      if (profileId != null) profileId,
    };

    for (final identifier in identifiers) {
      try {
        final response = await _supabase
            .from('patients')
            .select()
            .eq(
              'profile_id',
              identifier,
            )
            .limit(1);

        final rows = _rows(response);

        if (rows.isNotEmpty) {
          final patientId = _cleanId(
            rows.first['id'],
          );

          if (patientId != null) {
            return patientId;
          }
        }
      } catch (error) {
        debugPrint(
          'Patient lookup by profile_id '
          'failed for $identifier: $error',
        );
      }
    }

    for (final identifier in identifiers) {
      try {
        final response = await _supabase
            .from('patients')
            .select()
            .eq(
              'user_id',
              identifier,
            )
            .limit(1);

        final rows = _rows(response);

        if (rows.isNotEmpty) {
          final patientId = _cleanId(
            rows.first['id'],
          );

          if (patientId != null) {
            return patientId;
          }
        }
      } catch (error) {
        debugPrint(
          'Patient lookup by user_id '
          'failed for $identifier: $error',
        );
      }
    }

    return null;
  }

  Future<Map<String, Map<String, dynamic>>> _loadTemplates(
    Set<String> templateIds,
  ) async {
    if (templateIds.isEmpty) {
      return {};
    }

    try {
      final response = await _supabase
          .from(
            'hospital_form_templates',
          )
          .select()
          .inFilter(
            'id',
            templateIds.toList(),
          );

      final result = <String, Map<String, dynamic>>{};

      for (final row in _rows(response)) {
        final id = _cleanId(
          row['id'],
        );

        if (id != null) {
          result[id] = row;
        }
      }

      return result;
    } catch (error) {
      debugPrint(
        'Released Forms template lookup failed: $error',
      );

      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadTemplateVersions(
    Set<String> versionIds,
  ) async {
    if (versionIds.isEmpty) {
      return {};
    }

    try {
      final response = await _supabase
          .from(
            'hospital_form_template_versions',
          )
          .select()
          .inFilter(
            'id',
            versionIds.toList(),
          );

      final result = <String, Map<String, dynamic>>{};

      for (final row in _rows(response)) {
        final id = _cleanId(
          row['id'],
        );

        if (id != null) {
          result[id] = row;
        }
      }

      return result;
    } catch (error) {
      debugPrint(
        'Released Forms version lookup failed: $error',
      );

      return {};
    }
  }

  Future<String> _resolveHospitalName(
    String? hospitalId,
  ) async {
    if (hospitalId == null || hospitalId.isEmpty) {
      return 'Hospital';
    }

    try {
      final response = await _supabase
          .from('hospitals')
          .select(
            'name',
          )
          .eq(
            'id',
            hospitalId,
          )
          .maybeSingle();

      final name = response?['name']?.toString().trim();

      if (name != null && name.isNotEmpty) {
        return name;
      }
    } catch (error) {
      debugPrint(
        'Released Forms hospital-name lookup failed: $error',
      );
    }

    return 'Hospital';
  }

  bool _isReleasedInstance(
    Map<String, dynamic> row,
  ) {
    final status = _normalise(
      row['status'],
    );

    final finalized = status == 'finalized' ||
        status == 'finalised' ||
        status == 'completed' ||
        row['finalized_at'] != null ||
        row['finalised_at'] != null;

    final explicitRelease = _toBool(
          row['released_to_patient'],
        ) ||
        _toBool(
          row['patient_released'],
        ) ||
        _toBool(
          row['is_released_to_patient'],
        );

    final releaseTimestamp = row['released_to_patient_at'] != null ||
        row['patient_released_at'] != null ||
        row['released_at'] != null;

    return finalized && (explicitRelease || releaseTimestamp);
  }

  bool _toBool(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == 'true' || text == '1' || text == 'yes';
  }

  String _normalise(
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

  String _normaliseCategory(
    String value,
  ) {
    final text = _normalise(
      value,
    );

    if (text.contains(
          'admission',
        ) ||
        text.contains(
          'consent',
        ) ||
        text.contains(
          'privacy',
        )) {
      return 'Admission';
    }

    if (text.contains(
          'emergency',
        ) ||
        text.contains(
          'triage',
        )) {
      return 'Emergency';
    }

    if (text.contains(
          'nurs',
        ) ||
        text.contains(
          'observation',
        ) ||
        text.contains(
          'vital',
        )) {
      return 'Nursing';
    }

    if (text.contains(
          'medication',
        ) ||
        text.contains(
          'administration',
        ) ||
        text.contains(
          'mar',
        )) {
      return 'Medication';
    }

    if (text.contains(
          'pharmacy',
        ) ||
        text.contains(
          'dispens',
        ) ||
        text.contains(
          'collection',
        )) {
      return 'Pharmacy';
    }

    if (text.contains(
          'laboratory',
        ) ||
        text.contains(
          'lab_',
        ) ||
        text == 'lab' ||
        text.contains(
          'pathology',
        )) {
      return 'Laboratory';
    }

    if (text.contains(
          'imaging',
        ) ||
        text.contains(
          'radiology',
        ) ||
        text.contains(
          'xray',
        ) ||
        text.contains(
          'x_ray',
        )) {
      return 'Imaging';
    }

    if (text.contains(
      'discharge',
    )) {
      return 'Discharge';
    }

    if (text.contains(
          'transfer',
        ) ||
        text.contains(
          'handover',
        )) {
      return 'Transfer';
    }

    return 'Other';
  }

  List<Map<String, dynamic>> _rows(
    dynamic response,
  ) {
    if (response is! List) {
      return [];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => Map<String, dynamic>.from(
            row,
          ),
        )
        .toList();
  }

  String? _cleanId(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return fallback;
  }

  DateTime? _firstDate(
    Map<String, dynamic> row,
    List<String> columns,
  ) {
    for (final column in columns) {
      final value = row[column];

      if (value == null) {
        continue;
      }

      final parsed = DateTime.tryParse(
        value.toString(),
      );

      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  String _formatDate(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Date unavailable';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _cleanError(
    Object error,
  ) {
    if (error is PostgrestException) {
      final details = error.details?.toString().trim() ?? '';

      if (details.isNotEmpty &&
          details.toLowerCase() != 'null' &&
          details != error.message) {
        return '${error.message} $details';
      }

      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  List<_ReleasedFormRecord> get _visibleForms {
    final search = _searchController.text.trim().toLowerCase();

    return _forms.where(
      (
        form,
      ) {
        final matchesSearch = search.isEmpty ||
            form.title.toLowerCase().contains(
                  search,
                ) ||
            form.description.toLowerCase().contains(
                  search,
                ) ||
            form.category.toLowerCase().contains(
                  search,
                ) ||
            form.hospitalName.toLowerCase().contains(
                  search,
                ) ||
            form.code.toLowerCase().contains(
                  search,
                );

        final matchesFilter =
            _selectedFilter == 'All' || form.category == _selectedFilter;

        return matchesSearch && matchesFilter;
      },
    ).toList();
  }

  Future<void> _openForm(
    _ReleasedFormRecord form,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return _ReleasedFormReadOnlyPage(
            form: form,
          );
        },
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final visibleForms = _visibleForms;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Released Hospital Forms',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.refresh,
                  ),
          ),
        ],
      ),
      body: _buildBody(
        visibleForms,
      ),
    );
  }

  Widget _buildBody(
    List<_ReleasedFormRecord> visibleForms,
  ) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildHeader(),
          const SizedBox(
            height: 18,
          ),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search released forms',
              prefixIcon: const Icon(
                Icons.search,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        setState(
                          () {},
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
            height: 14,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map(
                (
                  filter,
                ) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      right: 8,
                    ),
                    child: ChoiceChip(
                      label: Text(
                        filter,
                      ),
                      selected: _selectedFilter == filter,
                      onSelected: (_) {
                        setState(
                          () {
                            _selectedFilter = filter;
                          },
                        );
                      },
                    ),
                  );
                },
              ).toList(),
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Text(
            '${visibleForms.length} released form'
            '${visibleForms.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          if (visibleForms.isEmpty)
            _buildEmptyState()
          else
            ...visibleForms.map(
              _buildFormCard,
            ),
          const SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius: BorderRadius.circular(
          22,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.folder_shared_outlined,
              color: Color(
                0xFF0F766E,
              ),
              size: 31,
            ),
          ),
          const SizedBox(
            width: 14,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Released Forms',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                const Text(
                  'Finalized hospital records released to you by authorized hospital staff.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (_patientId != null) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Patient record: ${_shortId(_patientId!)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(
    _ReleasedFormRecord form,
  ) {
    final color = _categoryColor(
      form.category,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(
          18,
        ),
        child: InkWell(
          onTap: () {
            _openForm(
              form,
            );
          },
          borderRadius: BorderRadius.circular(
            18,
          ),
          child: Padding(
            padding: const EdgeInsets.all(
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: 0.11,
                        ),
                        borderRadius: BorderRadius.circular(
                          15,
                        ),
                      ),
                      child: Icon(
                        _categoryIcon(
                          form.category,
                        ),
                        color: color,
                      ),
                    ),
                    const SizedBox(
                      width: 13,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            form.title,
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            form.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: context.cTextMuted,
                    ),
                  ],
                ),
                const SizedBox(
                  height: 13,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ReleasedFormChip(
                      icon: Icons.category_outlined,
                      label: form.category,
                      color: color,
                    ),
                    _ReleasedFormChip(
                      icon: Icons.local_hospital_outlined,
                      label: form.hospitalName,
                      color: context.cAccentReadable,
                    ),
                    _ReleasedFormChip(
                      icon: Icons.verified_outlined,
                      label: 'Finalized',
                      color: CorviaColors.success,
                    ),
                  ],
                ),
                const SizedBox(
                  height: 12,
                ),
                Divider(
                  color: context.cDivider,
                ),
                const SizedBox(
                  height: 8,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _ReleasedFormMeta(
                        icon: Icons.calendar_today_outlined,
                        label: 'Released',
                        value: _formatDate(
                          form.releasedAt,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: const _ReleasedFormMeta(
                        icon: Icons.lock_outline,
                        label: 'Access',
                        value: 'Read only',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtering =
        _searchController.text.trim().isNotEmpty || _selectedFilter != 'All';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        32,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            filtering ? Icons.search_off : Icons.folder_open_outlined,
            size: 54,
            color: context.cTextMuted,
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            filtering ? 'No matching released forms' : 'No released forms yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            filtering
                ? 'Try a different search or form category.'
                : 'Hospital forms will appear here after an authorized '
                    'staff member finalizes and releases them to you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 520,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              24,
            ),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                22,
              ),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  size: 58,
                  color: CorviaColors.danger,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'Released forms could not load',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SelectableText(
                  _errorMessage ?? 'Unknown released form error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadReleasedForms,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _categoryColor(
    String category,
  ) {
    switch (category) {
      case 'Admission':
        return Colors.blue.shade700;

      case 'Emergency':
        return CorviaColors.danger;

      case 'Nursing':
        return CorviaColors.accent;

      case 'Medication':
        return Colors.deepPurple;

      case 'Pharmacy':
        return Colors.teal.shade700;

      case 'Laboratory':
        return Colors.indigo;

      case 'Imaging':
        return Colors.blueGrey;

      case 'Discharge':
        return CorviaColors.success;

      case 'Transfer':
        return Colors.orange.shade800;

      default:
        return context.cAccentReadable;
    }
  }

  IconData _categoryIcon(
    String category,
  ) {
    switch (category) {
      case 'Admission':
        return Icons.assignment_ind_outlined;

      case 'Emergency':
        return Icons.emergency_outlined;

      case 'Nursing':
        return Icons.monitor_heart_outlined;

      case 'Medication':
        return Icons.medication_outlined;

      case 'Pharmacy':
        return Icons.local_pharmacy_outlined;

      case 'Laboratory':
        return Icons.biotech_outlined;

      case 'Imaging':
        return Icons.image_outlined;

      case 'Discharge':
        return Icons.exit_to_app_outlined;

      case 'Transfer':
        return Icons.swap_horiz_outlined;

      default:
        return Icons.description_outlined;
    }
  }

  String _shortId(
    String value,
  ) {
    final clean = value.trim();

    if (clean.length <= 8) {
      return clean;
    }

    return clean.substring(
      0,
      8,
    );
  }
}

class _ReleasedFormReadOnlyPage extends StatefulWidget {
  const _ReleasedFormReadOnlyPage({
    required this.form,
  });

  final _ReleasedFormRecord form;

  @override
  State<_ReleasedFormReadOnlyPage> createState() =>
      _ReleasedFormReadOnlyPageState();
}

class _ReleasedFormReadOnlyPageState extends State<_ReleasedFormReadOnlyPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;

  String? _errorMessage;

  List<_ReleasedAnswerRecord> _answers = [];

  Map<String, Map<String, dynamic>> _fieldsByKey = {};

  @override
  void initState() {
    super.initState();

    _loadForm();
  }

  Future<void> _openSecurePdf() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return HospitalFormPdfPreviewPage(
            instanceId: widget.form.instanceId,
            title: widget.form.title,
            patientVisibleOnly: true,
            requireReleasedToPatient: true,
          );
        },
      ),
    );
  }

  Future<void> _loadForm() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final valuesResponse = await _supabase
          .from(
            'hospital_form_instance_values',
          )
          .select()
          .eq(
            'instance_id',
            widget.form.instanceId,
          );

      final values = _releasedRows(
        valuesResponse,
      );

      await _loadFields();

      final answerRecords = <_ReleasedAnswerRecord>[];

      for (final value in values) {
        final fieldKey = _releasedCleanText(
          value['field_key'],
        );

        if (fieldKey == null) {
          continue;
        }

        final field = _fieldsByKey[fieldKey];

        final patientVisible = _isFieldPatientVisible(
          field,
        );

        if (!patientVisible) {
          continue;
        }

        final label = _releasedFirstText(
          [
            field?['field_label'],
            field?['label'],
            field?['title'],
            field?['name'],
            fieldKey,
          ],
          fallback: fieldKey,
        );

        final section = _releasedFirstText(
          [
            field?['section_title'],
            field?['section'],
            field?['section_key'],
          ],
          fallback: '',
        );

        final answer = _displayValue(
          value,
        );

        if (answer.trim().isEmpty) {
          continue;
        }

        answerRecords.add(
          _ReleasedAnswerRecord(
            fieldKey: fieldKey,
            label: label,
            section: section,
            answer: answer,
            order: _fieldOrder(
              field,
            ),
          ),
        );
      }

      answerRecords.sort(
        (
          first,
          second,
        ) {
          final sectionCompare = first.section.compareTo(
            second.section,
          );

          if (sectionCompare != 0) {
            return sectionCompare;
          }

          final orderCompare = first.order.compareTo(
            second.order,
          );

          if (orderCompare != 0) {
            return orderCompare;
          }

          return first.label.compareTo(
            second.label,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _answers = answerRecords;

        _loading = false;
      });
    } catch (error) {
      debugPrint(
        'Released form detail load error: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;

        _errorMessage = _releasedCleanError(
          error,
        );
      });
    }
  }

  Future<void> _loadFields() async {
    final versionId = widget.form.templateVersionId;

    if (versionId == null || versionId.isEmpty) {
      _fieldsByKey = {};
      return;
    }

    try {
      final response = await _supabase
          .from(
            'hospital_form_template_fields',
          )
          .select()
          .eq(
            'template_version_id',
            versionId,
          );

      final fields = _releasedRows(
        response,
      );

      final result = <String, Map<String, dynamic>>{};

      for (final field in fields) {
        final fieldKey = _releasedCleanText(
          field['field_key'],
        );

        if (fieldKey != null) {
          result[fieldKey] = field;
        }
      }

      _fieldsByKey = result;
    } catch (error) {
      debugPrint(
        'Released form field lookup failed: $error',
      );

      _fieldsByKey = {};
    }
  }

  bool _isFieldPatientVisible(
    Map<String, dynamic>? field,
  ) {
    if (field == null) {
      return true;
    }

    final values = [
      field['is_patient_visible'],
      field['patient_visible'],
      field['visible_to_patient'],
    ];

    for (final value in values) {
      if (value == null) {
        continue;
      }

      if (value is bool) {
        return value;
      }

      final text = value.toString().trim().toLowerCase();

      if (text == 'false' || text == '0' || text == 'no') {
        return false;
      }

      if (text == 'true' || text == '1' || text == 'yes') {
        return true;
      }
    }

    return true;
  }

  int _fieldOrder(
    Map<String, dynamic>? field,
  ) {
    if (field == null) {
      return 999999;
    }

    for (final key in const [
      'sort_order',
      'display_order',
      'field_order',
      'position',
      'order_index',
    ]) {
      final value = field[key];

      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      final parsed = int.tryParse(
        value.toString(),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return 999999;
  }

  String _displayValue(
    Map<String, dynamic> row,
  ) {
    final directText = _releasedFirstText(
      [
        row['value_text'],
        row['display_value'],
      ],
      fallback: '',
    );

    if (directText.isNotEmpty) {
      return directText;
    }

    final value = row['value'];

    if (value == null) {
      return '';
    }

    if (value is bool) {
      return value ? 'Yes' : 'No';
    }

    if (value is List) {
      return value
          .map(
            (item) => item.toString(),
          )
          .join(
            ', ',
          );
    }

    if (value is Map) {
      final textParts = <String>[];

      value.forEach(
        (
          key,
          nestedValue,
        ) {
          if (nestedValue == null) {
            return;
          }

          textParts.add(
            '${_prettyKey(key.toString())}: '
            '$nestedValue',
          );
        },
      );

      return textParts.join(
        '\n',
      );
    }

    return value.toString();
  }

  String _prettyKey(
    String value,
  ) {
    final words = value
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        )
        .split(
          RegExp(
            r'\s+',
          ),
        )
        .where(
          (word) => word.isNotEmpty,
        )
        .toList();

    return words
        .map(
          (word) => '${word[0].toUpperCase()}'
              '${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Text(
          widget.form.title,
        ),
        actions: [
          IconButton(
            tooltip: 'Open Secure PDF',
            onPressed: _openSecurePdf,
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: CorviaColors.accent,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: CorviaColors.danger,
                size: 56,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                'This released form could not load.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              SelectableText(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              ElevatedButton.icon(
                onPressed: _loadForm,
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

    return ListView(
      padding: const EdgeInsets.all(
        18,
      ),
      children: [
        _buildDocumentHeader(),
        const SizedBox(
          height: 18,
        ),
        if (_answers.isEmpty) _buildNoAnswers() else ..._buildAnswerSections(),
        const SizedBox(
          height: 24,
        ),
      ],
    );
  }

  Widget _buildDocumentHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: CorviaColors.success.withValues(
                    alpha: 0.11,
                  ),
                  borderRadius: BorderRadius.circular(
                    15,
                  ),
                ),

                // FIX:
                // This Icon must NOT be const because
                // CorviaColors.success is not compile-time constant.
                child: Icon(
                  Icons.verified_outlined,
                  color: CorviaColors.success,
                ),
              ),
              const SizedBox(
                width: 13,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.form.title,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      widget.form.description,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Divider(
            color: context.cDivider,
          ),
          const SizedBox(
            height: 10,
          ),
          _ReleasedDetailLine(
            label: 'Hospital',
            value: widget.form.hospitalName,
          ),
          _ReleasedDetailLine(
            label: 'Category',
            value: widget.form.category,
          ),
          const _ReleasedDetailLine(
            label: 'Status',
            value: 'Finalized',
          ),
          _ReleasedDetailLine(
            label: 'Released',
            value: _releasedFormatDate(
              widget.form.releasedAt,
            ),
          ),
          const _ReleasedDetailLine(
            label: 'Access',
            value: 'Patient read-only copy',
          ),
          if (widget.form.code.isNotEmpty)
            _ReleasedDetailLine(
              label: 'Form Code',
              value: widget.form.code,
            ),
          const SizedBox(
            height: 12,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openSecurePdf,
              icon: const Icon(
                Icons.picture_as_pdf_outlined,
              ),
              label: const Text(
                'Open Secure PDF',
              ),
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'Only patient-visible fields are included. '
            'The PDF is only available after the hospital '
            'has finalized and released this form to you.',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAnswerSections() {
    final bySection = <String, List<_ReleasedAnswerRecord>>{};

    for (final answer in _answers) {
      final section = answer.section.trim().isEmpty
          ? 'Form Details'
          : answer.section.trim();

      bySection
          .putIfAbsent(
            section,
            () => [],
          )
          .add(
            answer,
          );
    }

    final widgets = <Widget>[];

    for (final entry in bySection.entries) {
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: 14,
          ),
          padding: const EdgeInsets.all(
            17,
          ),
          decoration: BoxDecoration(
            color: context.cBgSecondary,
            borderRadius: BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color: context.cDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              ...entry.value.map(
                (
                  answer,
                ) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(
                      bottom: 10,
                    ),
                    padding: const EdgeInsets.all(
                      12,
                    ),
                    decoration: BoxDecoration(
                      color: context.cBgPrimary,
                      borderRadius: BorderRadius.circular(
                        13,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          answer.label,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        SelectableText(
                          answer.answer,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildNoAnswers() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        28,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.description_outlined,
            size: 48,
            color: context.cTextMuted,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'No patient-visible form answers',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'This form has been released, but there are no '
            'patient-visible values available to display.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleasedFormRecord {
  const _ReleasedFormRecord({
    required this.instanceId,
    required this.patientId,
    required this.title,
    required this.code,
    required this.category,
    required this.description,
    required this.status,
    required this.hospitalName,
    required this.rawInstance,
    this.hospitalId,
    this.admissionId,
    this.templateId,
    this.templateVersionId,
    this.finalizedAt,
    this.releasedAt,
    this.rawTemplate,
    this.rawVersion,
  });

  final String instanceId;
  final String patientId;

  final String? hospitalId;
  final String? admissionId;

  final String? templateId;
  final String? templateVersionId;

  final String title;
  final String code;
  final String category;
  final String description;
  final String status;
  final String hospitalName;

  final DateTime? finalizedAt;
  final DateTime? releasedAt;

  final Map<String, dynamic> rawInstance;

  final Map<String, dynamic>? rawTemplate;
  final Map<String, dynamic>? rawVersion;
}

class _ReleasedAnswerRecord {
  const _ReleasedAnswerRecord({
    required this.fieldKey,
    required this.label,
    required this.section,
    required this.answer,
    required this.order,
  });

  final String fieldKey;
  final String label;
  final String section;
  final String answer;
  final int order;
}

class _ReleasedFormChip extends StatelessWidget {
  const _ReleasedFormChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.09,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(
            width: 5,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 190,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleasedFormMeta extends StatelessWidget {
  const _ReleasedFormMeta({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: context.cTextMuted,
        ),
        const SizedBox(
          width: 7,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.cTextMuted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(
                height: 2,
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReleasedDetailLine extends StatelessWidget {
  const _ReleasedDetailLine({
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
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _releasedRows(
  dynamic response,
) {
  if (response is! List) {
    return [];
  }

  return response
      .whereType<Map>()
      .map(
        (row) => Map<String, dynamic>.from(
          row,
        ),
      )
      .toList();
}

String? _releasedCleanText(
  dynamic value,
) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }

  return text;
}

String _releasedFirstText(
  List<dynamic> values, {
  required String fallback,
}) {
  for (final value in values) {
    final text = value?.toString().trim();

    if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
      return text;
    }
  }

  return fallback;
}

String _releasedFormatDate(
  DateTime? date,
) {
  if (date == null) {
    return 'Date unavailable';
  }

  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

String _releasedCleanError(
  Object error,
) {
  if (error is PostgrestException) {
    final details = error.details?.toString().trim() ?? '';

    if (details.isNotEmpty &&
        details.toLowerCase() != 'null' &&
        details != error.message) {
      return '${error.message} $details';
    }

    return error.message;
  }

  return error.toString().replaceFirst(
        'Exception: ',
        '',
      );
}
