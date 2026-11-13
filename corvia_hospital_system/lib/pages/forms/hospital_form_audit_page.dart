import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalFormAuditPage extends StatefulWidget {
  const HospitalFormAuditPage({
    super.key,
    required this.instanceId,
    this.title,
  });

  final String instanceId;
  final String? title;

  @override
  State<HospitalFormAuditPage> createState() => _HospitalFormAuditPageState();
}

class _HospitalFormAuditPageState extends State<HospitalFormAuditPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;

  String? _errorMessage;

  Map<String, dynamic>? _instance;

  String _formTitle = 'Hospital Form';
  String _hospitalName = 'Hospital';
  String _patientName = 'Patient';

  String? _hospitalId;
  String? _patientId;
  String? _templateId;

  String _selectedFilter = 'All';

  List<_HospitalFormAuditRecord> _events = [];

  final Map<String, String> _actorNames = {};

  static const List<String> _filters = [
    'All',
    'Workflow',
    'Edits',
    'Signatures',
    'Exports',
    'Access',
    'Legal',
    'System',
  ];

  @override
  void initState() {
    super.initState();

    _loadAuditTrail();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadAuditTrail() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final cleanInstanceId = widget.instanceId.trim();

      if (cleanInstanceId.isEmpty) {
        throw Exception(
          'A hospital form instance ID is required.',
        );
      }

      if (_supabase.auth.currentUser == null) {
        throw Exception(
          'No signed-in Corvia account was found.',
        );
      }

      await _loadInstance(
        cleanInstanceId,
      );

      final results = await Future.wait<List<_HospitalFormAuditRecord>>(
        [
          _loadPrimaryAuditEvents(
            cleanInstanceId,
          ),
          _loadSignatureEvents(
            cleanInstanceId,
          ),
          _loadExportEvents(
            cleanInstanceId,
          ),
          _loadLegalHoldEvents(
            cleanInstanceId,
          ),
          _loadBreakGlassEvents(),
        ],
      );

      final combined = <_HospitalFormAuditRecord>[];

      for (final result in results) {
        combined.addAll(
          result,
        );
      }

      final deduplicated = _deduplicateEvents(
        combined,
      );

      await _resolveActorNames(
        deduplicated,
      );

      deduplicated.sort(
        (
          first,
          second,
        ) {
          final firstDate = first.occurredAt ?? DateTime(1970);

          final secondDate = second.occurredAt ?? DateTime(1970);

          return secondDate.compareTo(
            firstDate,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _events = deduplicated;

        _loading = false;
      });
    } catch (error) {
      debugPrint(
        'Hospital Form Audit load failed: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _events = [];
        _loading = false;
        _errorMessage = _cleanError(
          error,
        );
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
      await _loadAuditTrail();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadInstance(
    String instanceId,
  ) async {
    final response = await _supabase
        .from(
          'hospital_form_instances',
        )
        .select()
        .eq(
          'id',
          instanceId,
        )
        .maybeSingle();

    if (response == null) {
      throw Exception(
        'The selected hospital form could not be found.',
      );
    }

    final instance = Map<String, dynamic>.from(
      response,
    );

    _instance = instance;

    _hospitalId = _cleanId(
      instance['hospital_id'],
    );

    _patientId = _cleanId(
      instance['patient_id'],
    );

    _templateId = _cleanId(
      instance['template_id'],
    );

    await Future.wait([
      _resolveFormTitle(),
      _resolveHospitalName(),
      _resolvePatientName(),
    ]);
  }

  Future<void> _resolveFormTitle() async {
    final templateId = _templateId;

    if (templateId == null) {
      _formTitle = _firstText(
        [
          _instance?['title'],
          _instance?['form_name'],
        ],
        fallback: 'Hospital Form',
      );

      return;
    }

    try {
      final response = await _supabase
          .from(
            'hospital_form_templates',
          )
          .select()
          .eq(
            'id',
            templateId,
          )
          .maybeSingle();

      if (response == null) {
        return;
      }

      final template = Map<String, dynamic>.from(
        response,
      );

      _formTitle = _firstText(
        [
          template['display_name'],
          template['title'],
          template['name'],
          template['template_name'],
          template['code'],
          _instance?['title'],
        ],
        fallback: 'Hospital Form',
      );
    } catch (error) {
      debugPrint(
        'Audit form-title lookup failed: $error',
      );
    }
  }

  Future<void> _resolveHospitalName() async {
    final hospitalId = _hospitalId;

    if (hospitalId == null) {
      return;
    }

    try {
      final response = await _supabase
          .from('hospitals')
          .select()
          .eq(
            'id',
            hospitalId,
          )
          .maybeSingle();

      if (response == null) {
        return;
      }

      _hospitalName = _firstText(
        [
          response['name'],
          response['hospital_name'],
        ],
        fallback: 'Hospital',
      );
    } catch (error) {
      debugPrint(
        'Audit hospital lookup failed: $error',
      );
    }
  }

  Future<void> _resolvePatientName() async {
    final patientId = _patientId;

    if (patientId == null) {
      return;
    }

    try {
      final response = await _supabase
          .from('patients')
          .select()
          .eq(
            'id',
            patientId,
          )
          .maybeSingle();

      if (response == null) {
        return;
      }

      final patient = Map<String, dynamic>.from(
        response,
      );

      final directName = _firstText(
        [
          patient['full_name'],
          patient['display_name'],
          patient['name'],
        ],
        fallback: '',
      );

      if (directName.isNotEmpty) {
        _patientName = directName;

        return;
      }

      final profileId = _cleanId(
        patient['profile_id'],
      );

      final userId = _cleanId(
        patient['user_id'],
      );

      final identifiers = <String>{
        if (profileId != null) profileId,
        if (userId != null) userId,
      };

      for (final identifier in identifiers) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select()
              .eq(
                'id',
                identifier,
              )
              .maybeSingle();

          if (profile != null) {
            final name = _profileName(
              Map<String, dynamic>.from(
                profile,
              ),
            );

            if (name.isNotEmpty) {
              _patientName = name;

              return;
            }
          }
        } catch (_) {}
      }

      for (final identifier in identifiers) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select()
              .eq(
                'user_id',
                identifier,
              )
              .maybeSingle();

          if (profile != null) {
            final name = _profileName(
              Map<String, dynamic>.from(
                profile,
              ),
            );

            if (name.isNotEmpty) {
              _patientName = name;

              return;
            }
          }
        } catch (_) {}
      }

      _patientName = 'Patient ${_shortId(patientId)}';
    } catch (error) {
      debugPrint(
        'Audit patient lookup failed: $error',
      );
    }
  }

  Future<List<_HospitalFormAuditRecord>> _loadPrimaryAuditEvents(
    String instanceId,
  ) async {
    try {
      final response = await _supabase
          .from(
            'hospital_form_audit_events',
          )
          .select()
          .eq(
            'instance_id',
            instanceId,
          );

      final result = <_HospitalFormAuditRecord>[];

      for (final row in _rows(response)) {
        final action = _firstText(
          [
            row['event_type'],
            row['action'],
            row['event_name'],
            row['type'],
          ],
          fallback: 'audit_event',
        );

        result.add(
          _HospitalFormAuditRecord(
            id: _firstText(
              [
                row['id'],
              ],
              fallback: 'audit-${result.length}',
            ),
            action: action,
            title: _eventTitle(
              action,
            ),
            description: _auditDescription(
              row,
            ),
            category: _eventCategory(
              action,
            ),
            source: 'Audit Log',
            occurredAt: _firstDate(
              row,
              const [
                'created_at',
                'occurred_at',
                'event_at',
                'recorded_at',
                'updated_at',
              ],
            ),
            actorProfileId: _firstId(
              [
                row['actor_profile_id'],
                row['profile_id'],
                row['performed_by_profile_id'],
                row['created_by_profile_id'],
              ],
            ),
            actorUserId: _firstId(
              [
                row['actor_user_id'],
                row['user_id'],
                row['performed_by'],
                row['created_by'],
              ],
            ),
            actorRole: _firstText(
              [
                row['actor_role'],
                row['role'],
                row['performed_by_role'],
              ],
              fallback: '',
            ),
            metadata: _firstMap(
              [
                row['metadata'],
                row['event_data'],
                row['details'],
                row['payload'],
              ],
            ),
            raw: row,
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint(
        'Primary form audit lookup failed: $error',
      );

      return [];
    }
  }

  Future<List<_HospitalFormAuditRecord>> _loadSignatureEvents(
    String instanceId,
  ) async {
    try {
      final response = await _supabase
          .from(
            'hospital_form_signatures',
          )
          .select()
          .eq(
            'instance_id',
            instanceId,
          );

      final result = <_HospitalFormAuditRecord>[];

      for (final row in _rows(response)) {
        final signerName = _firstText(
          [
            row['signer_name'],
            row['signed_by_name'],
            row['name'],
          ],
          fallback: 'Electronic signer',
        );

        final signerRole = _firstText(
          [
            row['signer_role'],
            row['role'],
          ],
          fallback: 'signer',
        );

        final method = _firstText(
          [
            row['signature_method'],
            row['method'],
          ],
          fallback: 'electronic',
        );

        result.add(
          _HospitalFormAuditRecord(
            id: _firstText(
              [
                row['id'],
              ],
              fallback: 'signature-${result.length}',
            ),
            action: 'signed',
            title: 'Form Signed',
            description: '$signerName signed as '
                '${_prettyText(signerRole)} using '
                '${_prettyText(method)}.',
            category: 'Signatures',
            source: 'Signature Record',
            occurredAt: _firstDate(
              row,
              const [
                'signed_at',
                'created_at',
              ],
            ),
            actorProfileId: _firstId(
              [
                row['signer_profile_id'],
                row['profile_id'],
              ],
            ),
            actorUserId: _firstId(
              [
                row['signer_user_id'],
                row['user_id'],
              ],
            ),
            actorRole: signerRole,
            metadata: {
              if (_text(
                    row['signer_identifier'],
                  ) !=
                  null)
                'Signer identifier': row['signer_identifier'],
              'Signature method': method,
              if (_text(
                    row['witness_name'],
                  ) !=
                  null)
                'Witness': row['witness_name'],
              if (_text(
                    row['declaration_text'],
                  ) !=
                  null)
                'Declaration': row['declaration_text'],
            },
            raw: row,
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint(
        'Form signature audit lookup failed: $error',
      );

      return [];
    }
  }

  Future<List<_HospitalFormAuditRecord>> _loadExportEvents(
    String instanceId,
  ) async {
    try {
      final response = await _supabase
          .from(
            'hospital_form_exports',
          )
          .select()
          .eq(
            'instance_id',
            instanceId,
          );

      final result = <_HospitalFormAuditRecord>[];

      for (final row in _rows(response)) {
        final exportType = _firstText(
          [
            row['export_type'],
            row['action'],
            row['type'],
          ],
          fallback: 'pdf_export',
        );

        final fileName = _firstText(
          [
            row['file_name'],
            row['filename'],
          ],
          fallback: 'Hospital form PDF',
        );

        final destination = _firstText(
          [
            row['destination'],
          ],
          fallback: '',
        );

        result.add(
          _HospitalFormAuditRecord(
            id: _firstText(
              [
                row['id'],
              ],
              fallback: 'export-${result.length}',
            ),
            action: exportType,
            title: _exportTitle(
              exportType,
            ),
            description:
                destination.isEmpty ? fileName : '$fileName • $destination',
            category: 'Exports',
            source: 'Export Log',
            occurredAt: _firstDate(
              row,
              const [
                'created_at',
                'exported_at',
                'printed_at',
                'downloaded_at',
              ],
            ),
            actorProfileId: _firstId(
              [
                row['exported_by_profile_id'],
                row['actor_profile_id'],
                row['profile_id'],
              ],
            ),
            actorUserId: _firstId(
              [
                row['exported_by'],
                row['user_id'],
                row['actor_user_id'],
              ],
            ),
            actorRole: _firstText(
              [
                row['actor_role'],
                row['role'],
              ],
              fallback: '',
            ),
            metadata: _combineMetadata(
              row,
              const [
                'metadata',
              ],
              {
                if (_text(
                      row['file_name'],
                    ) !=
                    null)
                  'File': row['file_name'],
                if (_text(
                      row['destination'],
                    ) !=
                    null)
                  'Destination': row['destination'],
                if (_text(
                      row['reason'],
                    ) !=
                    null)
                  'Reason': row['reason'],
                if (row['file_size_bytes'] != null)
                  'File size': '${row['file_size_bytes']} bytes',
              },
            ),
            raw: row,
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint(
        'Form export audit lookup failed: $error',
      );

      return [];
    }
  }

  Future<List<_HospitalFormAuditRecord>> _loadLegalHoldEvents(
    String instanceId,
  ) async {
    try {
      final response = await _supabase
          .from(
            'hospital_form_legal_holds',
          )
          .select()
          .eq(
            'instance_id',
            instanceId,
          );

      final result = <_HospitalFormAuditRecord>[];

      for (final row in _rows(response)) {
        final active = _firstBool(
          [
            row['is_active'],
            row['active'],
          ],
          fallback: true,
        );

        final reason = _firstText(
          [
            row['hold_reason'],
            row['reason'],
          ],
          fallback: 'Legal hold applied to this form.',
        );

        result.add(
          _HospitalFormAuditRecord(
            id: _firstText(
              [
                row['id'],
              ],
              fallback: 'legal-${result.length}',
            ),
            action: active ? 'legal_hold_placed' : 'legal_hold_released',
            title: active ? 'Legal Hold Applied' : 'Legal Hold Released',
            description: reason,
            category: 'Legal',
            source: 'Legal Hold',
            occurredAt: _firstDate(
              row,
              const [
                'created_at',
                'placed_at',
                'updated_at',
                'released_at',
              ],
            ),
            actorProfileId: _firstId(
              [
                row['placed_by_profile_id'],
                row['created_by_profile_id'],
                row['actor_profile_id'],
              ],
            ),
            actorUserId: _firstId(
              [
                row['placed_by'],
                row['created_by'],
                row['user_id'],
              ],
            ),
            actorRole: _firstText(
              [
                row['actor_role'],
                row['role'],
              ],
              fallback: '',
            ),
            metadata: {
              if (_text(
                    row['reference_number'],
                  ) !=
                  null)
                'Reference': row['reference_number'],
              'Active': active,
              'Reason': reason,
            },
            raw: row,
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint(
        'Form legal-hold audit lookup failed: $error',
      );

      return [];
    }
  }

  Future<List<_HospitalFormAuditRecord>> _loadBreakGlassEvents() async {
    final hospitalId = _hospitalId;

    final patientId = _patientId;

    if (hospitalId == null || patientId == null) {
      return [];
    }

    try {
      final response = await _supabase
          .from(
            'hospital_form_break_glass_sessions',
          )
          .select()
          .eq(
            'hospital_id',
            hospitalId,
          )
          .eq(
            'patient_id',
            patientId,
          );

      final result = <_HospitalFormAuditRecord>[];

      for (final row in _rows(response)) {
        final start = _firstDate(
          row,
          const [
            'started_at',
            'created_at',
            'granted_at',
          ],
        );

        final end = _firstDate(
          row,
          const [
            'ended_at',
            'closed_at',
            'revoked_at',
          ],
        );

        final reason = _firstText(
          [
            row['reason'],
            row['access_reason'],
          ],
          fallback: 'Emergency access reason not recorded.',
        );

        result.add(
          _HospitalFormAuditRecord(
            id: _firstText(
              [
                row['id'],
              ],
              fallback: 'break-glass-${result.length}',
            ),
            action: end == null ? 'break_glass_started' : 'break_glass_session',
            title: end == null
                ? 'Break-Glass Access Started'
                : 'Break-Glass Access Session',
            description: reason,
            category: 'Access',
            source: 'Break-Glass',
            occurredAt: start,
            actorProfileId: _firstId(
              [
                row['profile_id'],
                row['actor_profile_id'],
                row['created_by_profile_id'],
                row['started_by_profile_id'],
              ],
            ),
            actorUserId: _firstId(
              [
                row['user_id'],
                row['created_by'],
                row['started_by'],
              ],
            ),
            actorRole: _firstText(
              [
                row['role'],
                row['actor_role'],
              ],
              fallback: '',
            ),
            metadata: {
              'Reason': reason,
              if (start != null)
                'Started': _formatDateTime(
                  start,
                ),
              if (end != null)
                'Ended': _formatDateTime(
                  end,
                ),
              if (_firstDate(
                    row,
                    const [
                      'expires_at',
                    ],
                  ) !=
                  null)
                'Expires': _formatDateTime(
                  _firstDate(
                    row,
                    const [
                      'expires_at',
                    ],
                  )!,
                ),
            },
            raw: row,
          ),
        );
      }

      return result;
    } catch (error) {
      debugPrint(
        'Break-glass audit lookup skipped: $error',
      );

      return [];
    }
  }

  Future<void> _resolveActorNames(
    List<_HospitalFormAuditRecord> events,
  ) async {
    _actorNames.clear();

    final profileIds = events
        .map(
          (
            event,
          ) =>
              event.actorProfileId,
        )
        .whereType<String>()
        .where(
          (
            id,
          ) =>
              id.isNotEmpty,
        )
        .toSet();

    final userIds = events
        .map(
          (
            event,
          ) =>
              event.actorUserId,
        )
        .whereType<String>()
        .where(
          (
            id,
          ) =>
              id.isNotEmpty,
        )
        .toSet();

    if (profileIds.isNotEmpty) {
      try {
        final response = await _supabase.from('profiles').select().inFilter(
              'id',
              profileIds.toList(),
            );

        for (final row in _rows(response)) {
          final id = _cleanId(
            row['id'],
          );

          if (id != null) {
            _actorNames[id] = _profileName(
              row,
            );
          }
        }
      } catch (error) {
        debugPrint(
          'Audit actor profile lookup failed: $error',
        );
      }
    }

    if (userIds.isNotEmpty) {
      try {
        final response = await _supabase.from('profiles').select().inFilter(
              'user_id',
              userIds.toList(),
            );

        for (final row in _rows(response)) {
          final userId = _cleanId(
            row['user_id'],
          );

          if (userId != null) {
            _actorNames[userId] = _profileName(
              row,
            );
          }

          final profileId = _cleanId(
            row['id'],
          );

          if (profileId != null) {
            _actorNames[profileId] = _profileName(
              row,
            );
          }
        }
      } catch (error) {
        debugPrint(
          'Audit actor user lookup failed: $error',
        );
      }
    }
  }

  List<_HospitalFormAuditRecord> _deduplicateEvents(
    List<_HospitalFormAuditRecord> events,
  ) {
    final seen = <String>{};

    final result = <_HospitalFormAuditRecord>[];

    for (final event in events) {
      final timestamp = event.occurredAt;

      final secondKey = timestamp == null
          ? 'no-time'
          : '${timestamp.year}-'
              '${timestamp.month}-'
              '${timestamp.day}-'
              '${timestamp.hour}-'
              '${timestamp.minute}-'
              '${timestamp.second}';

      final key = '${_normalise(event.action)}|'
          '$secondKey|'
          '${event.actorProfileId ?? event.actorUserId ?? ''}|'
          '${event.description.toLowerCase().trim()}';

      if (seen.add(key)) {
        result.add(
          event,
        );
      }
    }

    return result;
  }

  List<_HospitalFormAuditRecord> get _visibleEvents {
    final search = _searchController.text.trim().toLowerCase();

    return _events.where(
      (
        event,
      ) {
        final actor = _actorName(
          event,
        ).toLowerCase();

        final matchesSearch = search.isEmpty ||
            event.title.toLowerCase().contains(
                  search,
                ) ||
            event.description.toLowerCase().contains(
                  search,
                ) ||
            event.action.toLowerCase().contains(
                  search,
                ) ||
            event.category.toLowerCase().contains(
                  search,
                ) ||
            event.source.toLowerCase().contains(
                  search,
                ) ||
            actor.contains(
              search,
            );

        final matchesFilter =
            _selectedFilter == 'All' || event.category == _selectedFilter;

        return matchesSearch && matchesFilter;
      },
    ).toList();
  }

  String _actorName(
    _HospitalFormAuditRecord event,
  ) {
    final profileId = event.actorProfileId;

    if (profileId != null &&
        _actorNames.containsKey(
          profileId,
        )) {
      return _actorNames[profileId]!;
    }

    final userId = event.actorUserId;

    if (userId != null &&
        _actorNames.containsKey(
          userId,
        )) {
      return _actorNames[userId]!;
    }

    if (event.actorRole.isNotEmpty) {
      return _prettyText(
        event.actorRole,
      );
    }

    return 'System / Unknown Actor';
  }

  int _countCategory(
    String category,
  ) {
    return _events
        .where(
          (
            event,
          ) =>
              event.category == category,
        )
        .length;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final events = _visibleEvents;

    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : 'Form Audit History';

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Text(
          title,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Audit',
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
        events,
      ),
    );
  }

  Widget _buildBody(
    List<_HospitalFormAuditRecord> events,
  ) {
    if (_loading) {
      return _buildLoadingState();
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
          _buildStats(),
          const SizedBox(
            height: 18,
          ),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(
                () {},
              );
            },
            decoration: InputDecoration(
              hintText: 'Search audit history',
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Audit Timeline',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${events.length} event'
                '${events.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          if (events.isEmpty)
            _buildEmptyState()
          else
            _buildTimeline(
              events,
            ),
          const SizedBox(
            height: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: CorviaColors.accent,
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            'Loading form audit history...',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w700,
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 29,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.history_outlined,
              color: Color(
                0xFF0F766E,
              ),
              size: 30,
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
                  _formTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  '$_patientName • $_hospitalName',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(
                  height: 7,
                ),
                Text(
                  'Instance ${_shortId(widget.instanceId)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      _AuditStat(
        label: 'All Events',
        value: _events.length,
        icon: Icons.history,
        color: context.cAccentReadable,
      ),
      _AuditStat(
        label: 'Workflow',
        value: _countCategory(
          'Workflow',
        ),
        icon: Icons.account_tree_outlined,
        color: Colors.blue,
      ),
      _AuditStat(
        label: 'Signatures',
        value: _countCategory(
          'Signatures',
        ),
        icon: Icons.draw_outlined,
        color: Colors.deepPurple,
      ),
      _AuditStat(
        label: 'Exports',
        value: _countCategory(
          'Exports',
        ),
        icon: Icons.picture_as_pdf_outlined,
        color: Colors.orange.shade800,
      ),
      _AuditStat(
        label: 'Access',
        value: _countCategory(
          'Access',
        ),
        icon: Icons.security_outlined,
        color: CorviaColors.danger,
      ),
      _AuditStat(
        label: 'Legal',
        value: _countCategory(
          'Legal',
        ),
        icon: Icons.gavel_outlined,
        color: Colors.brown,
      ),
    ];

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final columns = constraints.maxWidth >= 1000
            ? 6
            : constraints.maxWidth >= 700
                ? 3
                : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 108,
          ),
          itemBuilder: (
            context,
            index,
          ) {
            final stat = stats[index];

            return Container(
              padding: const EdgeInsets.all(
                13,
              ),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: context.cDivider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: stat.color.withValues(
                        alpha: 0.10,
                      ),
                      borderRadius: BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Icon(
                      stat.icon,
                      color: stat.color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.value.toString(),
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          stat.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeline(
    List<_HospitalFormAuditRecord> events,
  ) {
    return Column(
      children: List.generate(
        events.length,
        (
          index,
        ) {
          final event = events[index];

          final isLast = index == events.length - 1;

          return _buildTimelineEvent(
            event,
            isLast: isLast,
          );
        },
      ),
    );
  }

  Widget _buildTimelineEvent(
    _HospitalFormAuditRecord event, {
    required bool isLast,
  }) {
    final color = _categoryColor(
      event.category,
    );

    final actor = _actorName(
      event,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: 0.12,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(
                        alpha: 0.28,
                      ),
                    ),
                  ),
                  child: Icon(
                    _categoryIcon(
                      event.category,
                      event.action,
                    ),
                    size: 18,
                    color: color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(
                        vertical: 5,
                      ),
                      color: context.cDivider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(
            width: 7,
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(
                bottom: isLast ? 0 : 12,
              ),
              padding: const EdgeInsets.all(
                15,
              ),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(
                  17,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: TextStyle(
                                color: context.cTextPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(
                              height: 3,
                            ),
                            Text(
                              _formatDateTime(
                                event.occurredAt,
                              ),
                              style: TextStyle(
                                color: context.cTextMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      _AuditCategoryPill(
                        label: event.category,
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Text(
                    event.description,
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _AuditInfoChip(
                        icon: Icons.person_outline,
                        label: actor,
                      ),
                      if (event.actorRole.isNotEmpty)
                        _AuditInfoChip(
                          icon: Icons.badge_outlined,
                          label: _prettyText(
                            event.actorRole,
                          ),
                        ),
                      _AuditInfoChip(
                        icon: Icons.storage_outlined,
                        label: event.source,
                      ),
                    ],
                  ),
                  if (event.metadata.isNotEmpty) ...[
                    const SizedBox(
                      height: 12,
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(
                        top: 4,
                      ),
                      title: Text(
                        'Event Details',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      children: _buildMetadataRows(
                        event.metadata,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMetadataRows(
    Map<String, dynamic> metadata,
  ) {
    final entries = metadata.entries
        .where(
          (
            entry,
          ) =>
              entry.value != null,
        )
        .toList();

    if (entries.isEmpty) {
      return [
        Text(
          'No additional event details.',
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      ];
    }

    return entries.map(
      (
        entry,
      ) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: 7,
          ),
          padding: const EdgeInsets.all(
            10,
          ),
          decoration: BoxDecoration(
            color: context.cBgPrimary,
            borderRadius: BorderRadius.circular(
              10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _prettyText(
                  entry.key,
                ),
                style: TextStyle(
                  color: context.cTextMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              SelectableText(
                _displayMetadataValue(
                  entry.value,
                ),
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    ).toList();
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
            filtering ? Icons.search_off : Icons.history_toggle_off_outlined,
            color: context.cTextMuted,
            size: 52,
          ),
          const SizedBox(
            height: 13,
          ),
          Text(
            filtering ? 'No matching audit events' : 'No audit history found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            filtering
                ? 'Try another search term or audit category.'
                : 'Audit events will appear as this form is created, '
                    'edited, signed, finalized, released or exported.',
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
            maxWidth: 540,
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
                  Icons.history_toggle_off_outlined,
                  color: CorviaColors.danger,
                  size: 58,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'Form audit history could not load',
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
                  _errorMessage ?? 'Unknown form audit error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadAuditTrail,
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

  String _auditDescription(
    Map<String, dynamic> row,
  ) {
    final explicit = _firstText(
      [
        row['description'],
        row['message'],
        row['summary'],
        row['reason'],
      ],
      fallback: '',
    );

    if (explicit.isNotEmpty) {
      return explicit;
    }

    final fieldKey = _firstText(
      [
        row['field_key'],
      ],
      fallback: '',
    );

    final oldValue = row['old_value'];

    final newValue = row['new_value'];

    if (fieldKey.isNotEmpty && (oldValue != null || newValue != null)) {
      return 'Field "${_prettyText(fieldKey)}" was updated.';
    }

    return 'Hospital form audit event recorded.';
  }

  String _eventTitle(
    String action,
  ) {
    final value = _normalise(
      action,
    );

    if (value.contains(
      'create',
    )) {
      return 'Form Created';
    }

    if (value.contains(
          'save',
        ) ||
        value.contains(
          'value',
        ) ||
        value.contains(
          'edit',
        ) ||
        value.contains(
          'amend',
        )) {
      return 'Form Updated';
    }

    if (value.contains(
      'submit',
    )) {
      return 'Form Submitted';
    }

    if (value.contains(
      'sign',
    )) {
      return 'Form Signed';
    }

    if (value.contains(
          'final',
        ) ||
        value.contains(
          'complete',
        )) {
      return 'Form Finalized';
    }

    if (value.contains(
          'release',
        ) &&
        value.contains(
          'patient',
        )) {
      return 'Released to Patient';
    }

    if (value.contains(
      'export',
    )) {
      return 'Form Exported';
    }

    if (value.contains(
      'print',
    )) {
      return 'Form Printed';
    }

    if (value.contains(
          'download',
        ) ||
        value.contains(
          'share',
        )) {
      return 'Form Shared / Downloaded';
    }

    if (value.contains(
          'break_glass',
        ) ||
        value.contains(
          'breakglass',
        )) {
      return 'Break-Glass Access';
    }

    if (value.contains(
      'legal',
    )) {
      return 'Legal Hold Event';
    }

    return _prettyText(
      action,
    );
  }

  String _eventCategory(
    String action,
  ) {
    final value = _normalise(
      action,
    );

    if (value.contains(
          'sign',
        ) ||
        value.contains(
          'signature',
        )) {
      return 'Signatures';
    }

    if (value.contains(
          'export',
        ) ||
        value.contains(
          'print',
        ) ||
        value.contains(
          'download',
        ) ||
        value.contains(
          'share',
        ) ||
        value.contains(
          'pdf',
        )) {
      return 'Exports';
    }

    if (value.contains(
          'break_glass',
        ) ||
        value.contains(
          'access',
        ) ||
        value.contains(
          'view',
        ) ||
        value.contains(
          'read',
        )) {
      return 'Access';
    }

    if (value.contains(
          'legal',
        ) ||
        value.contains(
          'hold',
        )) {
      return 'Legal';
    }

    if (value.contains(
          'save',
        ) ||
        value.contains(
          'edit',
        ) ||
        value.contains(
          'value',
        ) ||
        value.contains(
          'amend',
        ) ||
        value.contains(
          'field',
        )) {
      return 'Edits';
    }

    if (value.contains(
          'create',
        ) ||
        value.contains(
          'submit',
        ) ||
        value.contains(
          'final',
        ) ||
        value.contains(
          'release',
        ) ||
        value.contains(
          'complete',
        )) {
      return 'Workflow';
    }

    return 'System';
  }

  String _exportTitle(
    String exportType,
  ) {
    final value = _normalise(
      exportType,
    );

    if (value.contains(
      'print',
    )) {
      return 'PDF Printed';
    }

    if (value.contains(
      'share',
    )) {
      return 'PDF Shared / Exported';
    }

    if (value.contains(
      'download',
    )) {
      return 'PDF Downloaded';
    }

    return 'PDF Exported';
  }

  Color _categoryColor(
    String category,
  ) {
    switch (category) {
      case 'Workflow':
        return Colors.blue.shade700;

      case 'Edits':
        return Colors.teal;

      case 'Signatures':
        return Colors.deepPurple;

      case 'Exports':
        return Colors.orange.shade800;

      case 'Access':
        return CorviaColors.danger;

      case 'Legal':
        return Colors.brown;

      default:
        return context.cAccentReadable;
    }
  }

  IconData _categoryIcon(
    String category,
    String action,
  ) {
    switch (category) {
      case 'Workflow':
        if (_normalise(
          action,
        ).contains(
          'release',
        )) {
          return Icons.folder_shared_outlined;
        }

        if (_normalise(
          action,
        ).contains(
          'final',
        )) {
          return Icons.verified_outlined;
        }

        return Icons.account_tree_outlined;

      case 'Edits':
        return Icons.edit_note_outlined;

      case 'Signatures':
        return Icons.draw_outlined;

      case 'Exports':
        return Icons.picture_as_pdf_outlined;

      case 'Access':
        return Icons.security_outlined;

      case 'Legal':
        return Icons.gavel_outlined;

      default:
        return Icons.settings_outlined;
    }
  }

  String _profileName(
    Map<String, dynamic> row,
  ) {
    final direct = _firstText(
      [
        row['full_name'],
        row['display_name'],
        row['name'],
      ],
      fallback: '',
    );

    if (direct.isNotEmpty) {
      return direct;
    }

    final first = _firstText(
      [
        row['first_name'],
        row['firstname'],
      ],
      fallback: '',
    );

    final last = _firstText(
      [
        row['surname'],
        row['last_name'],
        row['lastname'],
      ],
      fallback: '',
    );

    final combined = '$first $last'.trim();

    if (combined.isNotEmpty) {
      return combined;
    }

    return _firstText(
      [
        row['email'],
      ],
      fallback: 'Corvia User',
    );
  }

  String _displayMetadataValue(
    dynamic value,
  ) {
    if (value == null) {
      return '-';
    }

    if (value is bool) {
      return value ? 'Yes' : 'No';
    }

    if (value is List || value is Map) {
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

    return value.toString();
  }

  Map<String, dynamic> _combineMetadata(
    Map<String, dynamic> row,
    List<String> metadataColumns,
    Map<String, dynamic> extra,
  ) {
    final result = <String, dynamic>{};

    for (final column in metadataColumns) {
      final value = row[column];

      if (value is Map) {
        result.addAll(
          Map<String, dynamic>.from(
            value,
          ),
        );
      } else if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(
            value,
          );

          if (decoded is Map) {
            result.addAll(
              Map<String, dynamic>.from(
                decoded,
              ),
            );
          }
        } catch (_) {}
      }
    }

    result.addAll(
      extra,
    );

    result.removeWhere(
      (
        key,
        value,
      ) =>
          value == null || (value is String && value.trim().isEmpty),
    );

    return result;
  }

  Map<String, dynamic> _firstMap(
    List<dynamic> values,
  ) {
    for (final value in values) {
      if (value is Map) {
        return Map<String, dynamic>.from(
          value,
        );
      }

      if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(
            value,
          );

          if (decoded is Map) {
            return Map<String, dynamic>.from(
              decoded,
            );
          }
        } catch (_) {}
      }
    }

    return {};
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
          (
            row,
          ) =>
              Map<String, dynamic>.from(
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

  String? _text(
    dynamic value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return text;
  }

  String? _firstId(
    List<dynamic> values,
  ) {
    for (final value in values) {
      final id = _cleanId(
        value,
      );

      if (id != null) {
        return id;
      }
    }

    return null;
  }

  String _firstText(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = _text(
        value,
      );

      if (text != null) {
        return text;
      }
    }

    return fallback;
  }

  bool _firstBool(
    List<dynamic> values, {
    required bool fallback,
  }) {
    for (final value in values) {
      if (value == null) {
        continue;
      }

      if (value is bool) {
        return value;
      }

      if (value is num) {
        return value != 0;
      }

      final text = value.toString().trim().toLowerCase();

      if (text == 'true' || text == '1' || text == 'yes') {
        return true;
      }

      if (text == 'false' || text == '0' || text == 'no') {
        return false;
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

      if (value is DateTime) {
        return value.toLocal();
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

  String _prettyText(
    String value,
  ) {
    final clean = value
        .trim()
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        );

    if (clean.isEmpty) {
      return 'Unknown';
    }

    return clean
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
      ) {
        if (word.length == 1) {
          return word.toUpperCase();
        }

        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(
      ' ',
    );
  }

  String _formatDateTime(
    DateTime? value,
  ) {
    if (value == null) {
      return 'Time not recorded';
    }

    final date = value.toLocal();

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
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
}

class _HospitalFormAuditRecord {
  const _HospitalFormAuditRecord({
    required this.id,
    required this.action,
    required this.title,
    required this.description,
    required this.category,
    required this.source,
    required this.actorRole,
    required this.metadata,
    required this.raw,
    this.occurredAt,
    this.actorProfileId,
    this.actorUserId,
  });

  final String id;

  final String action;

  final String title;

  final String description;

  final String category;

  final String source;

  final DateTime? occurredAt;

  final String? actorProfileId;

  final String? actorUserId;

  final String actorRole;

  final Map<String, dynamic> metadata;

  final Map<String, dynamic> raw;
}

class _AuditStat {
  const _AuditStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;

  final int value;

  final IconData icon;

  final Color color;
}

class _AuditCategoryPill extends StatelessWidget {
  const _AuditCategoryPill({
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
      constraints: const BoxConstraints(
        maxWidth: 110,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AuditInfoChip extends StatelessWidget {
  const _AuditInfoChip({
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
      constraints: const BoxConstraints(
        maxWidth: 230,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          999,
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
            size: 13,
            color: context.cTextMuted,
          ),
          const SizedBox(
            width: 5,
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
