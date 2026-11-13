import 'package:flutter/material.dart';

import '../../services/hospital_form_engine_service.dart';
import 'dynamic_hospital_form_page.dart';

class HospitalFormsPage extends StatefulWidget {
  const HospitalFormsPage({
    super.key,
    required this.hospitalId,
    this.patientId,
    this.admissionId,
    this.contextType,
    this.contextId,
    this.title = 'Hospital Forms',
    this.patientVisibleOnly = false,
    this.allowCreate = true,
  });

  final String hospitalId;
  final String? patientId;
  final String? admissionId;

  final String? contextType;
  final String? contextId;

  final String title;

  final bool patientVisibleOnly;
  final bool allowCreate;

  @override
  State<HospitalFormsPage> createState() {
    return _HospitalFormsPageState();
  }
}

class _HospitalFormsPageState extends State<HospitalFormsPage> {
  final HospitalFormEngineService _service = HospitalFormEngineService();

  final TextEditingController _searchController = TextEditingController();

  List<HospitalFormTemplateRecord> _templates = const [];
  List<HospitalFormInstanceRecord> _instances = const [];

  bool _loading = true;
  bool _startingForm = false;

  String? _errorMessage;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final templates = await _service.loadTemplates(
        hospitalId: widget.hospitalId,
        activeOnly: true,
        documentClassification:
            widget.patientVisibleOnly ? 'patient_visible' : null,
      );

      List<HospitalFormInstanceRecord> instances = const [];

      try {
        if (widget.patientId != null && widget.patientId!.trim().isNotEmpty) {
          instances = await _service.loadPatientForms(
            patientId: widget.patientId!.trim(),
          );
        } else if (widget.admissionId != null &&
            widget.admissionId!.trim().isNotEmpty) {
          instances = await _service.loadAdmissionForms(
            admissionId: widget.admissionId!.trim(),
          );
        } else {
          instances = await _service.loadInstances(
            hospitalId: widget.hospitalId,
          );
        }
      } catch (_) {
        /*
         * A role may have access to templates without having permission
         * to load every form instance in the hospital.
         */
        instances = const [];
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _templates = templates;
        _instances = instances;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  List<String> get _categories {
    final categories = _templates
        .map((template) => template.category)
        .where((category) => category.trim().isNotEmpty)
        .toSet()
        .toList();

    categories.sort();

    return categories;
  }

  List<HospitalFormTemplateRecord> get _filteredTemplates {
    final search = _searchController.text.trim().toLowerCase();

    return _templates.where((template) {
      if (_selectedCategory != null && template.category != _selectedCategory) {
        return false;
      }

      if (search.isEmpty) {
        return true;
      }

      final searchableText = [
        template.name,
        template.code,
        template.category,
        template.department ?? '',
        template.description ?? '',
      ].join(' ').toLowerCase();

      return searchableText.contains(search);
    }).toList(growable: false);
  }

  Future<void> _startTemplate(
    HospitalFormTemplateRecord template,
  ) async {
    if (_startingForm) {
      return;
    }

    if (template.requiresPatient &&
        (widget.patientId == null || widget.patientId!.trim().isEmpty)) {
      _showMessage(
        'This form requires a patient record.',
        isError: true,
      );
      return;
    }

    if (template.requiresAdmission &&
        (widget.admissionId == null || widget.admissionId!.trim().isEmpty)) {
      _showMessage(
        'This form requires an active hospital admission.',
        isError: true,
      );
      return;
    }

    setState(() {
      _startingForm = true;
    });

    try {
      final instanceId = await _service.startFormInstance(
        templateId: template.id,
        patientId: widget.patientId,
        admissionId: widget.admissionId,
        contextType: widget.contextType,
        contextId: widget.contextId,
        workflowMetadata: {
          'opened_from': 'hospital_forms_page',
          'template_code': template.code,
        },
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) {
            return DynamicHospitalFormPage(
              instanceId: instanceId,
            );
          },
        ),
      );

      await _loadPage();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _friendlyError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _startingForm = false;
        });
      }
    }
  }

  Future<void> _openInstance(
    HospitalFormInstanceRecord instance,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return DynamicHospitalFormPage(
            instanceId: instance.id,
          );
        },
      ),
    );

    await _loadPage();
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _loadPage,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.description_outlined),
                text: 'Templates',
              ),
              Tab(
                icon: Icon(Icons.folder_copy_outlined),
                text: 'Patient Forms',
              ),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return _ErrorState(
        message: _errorMessage!,
        onRetry: _loadPage,
      );
    }

    return TabBarView(
      children: [
        _buildTemplatesTab(),
        _buildInstancesTab(),
      ],
    );
  }

  Widget _buildTemplatesTab() {
    final templates = _filteredTemplates;

    return RefreshIndicator(
      onRefresh: _loadPage,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _buildTemplateFilters(),
          ),
          if (_templates.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.description_outlined,
                title: 'No forms available',
                message:
                    'No active hospital form templates are available for this account.',
              ),
            )
          else if (templates.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.search_off,
                title: 'No matching forms',
                message: 'Change the search text or category filter.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24,
              ),
              sliver: SliverList.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) {
                  return const SizedBox(height: 12);
                },
                itemBuilder: (context, index) {
                  final template = templates[index];

                  return _TemplateCard(
                    template: template,
                    allowCreate: widget.allowCreate && !_startingForm,
                    onStart: () {
                      _startTemplate(template);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTemplateFilters() {
    final categories = _categories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        14,
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Search forms',
              hintText: 'Admission, nursing, laboratory...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                _selectedCategory ?? 'all',
              ),
              initialValue: _selectedCategory ?? '',
              decoration: const InputDecoration(
                labelText: 'Form category',
                prefixIcon: Icon(
                  Icons.category_outlined,
                ),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('All categories'),
                ),
                ...categories.map(
                  (category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(
                        _humanize(category),
                      ),
                    );
                  },
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCategory =
                      value == null || value.isEmpty ? null : value;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstancesTab() {
    if (_instances.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPage,
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'No hospital forms yet',
                message:
                    'Forms created for this patient or admission will appear here.',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _instances.length,
        separatorBuilder: (_, __) {
          return const SizedBox(height: 12);
        },
        itemBuilder: (context, index) {
          final instance = _instances[index];

          return _InstanceCard(
            instance: instance,
            onOpen: () {
              _openInstance(instance);
            },
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.allowCreate,
    required this.onStart,
  });

  final HospitalFormTemplateRecord template;
  final bool allowCreate;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final classificationColor = _classificationColor(
      context,
      template.documentClassification,
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: classificationColor.withAlpha(28),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _templateIcon(template.category),
                    color: classificationColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template.department ?? template.displayCategory,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  text: _humanize(
                    template.documentClassification,
                  ),
                  color: classificationColor,
                ),
              ],
            ),
            if (template.description != null &&
                template.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(template.description!),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (template.requiresPatient)
                  const _InfoChip(
                    icon: Icons.person_outline,
                    label: 'Patient required',
                  ),
                if (template.requiresAdmission)
                  const _InfoChip(
                    icon: Icons.local_hospital_outlined,
                    label: 'Admission required',
                  ),
                if (template.requiresBreakGlass)
                  const _InfoChip(
                    icon: Icons.lock_open_outlined,
                    label: 'Break-glass access',
                  ),
                _InfoChip(
                  icon: Icons.verified_outlined,
                  label: template.status == 'active'
                      ? 'Active template'
                      : _humanize(template.status),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: allowCreate ? onStart : null,
                icon: const Icon(Icons.add),
                label: Text(
                  allowCreate ? 'Start form' : 'Creating form...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({
    required this.instance,
    required this.onOpen,
  });

  final HospitalFormInstanceRecord instance;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(
      context,
      instance.status,
    );

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.templateName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      instance.documentNumber,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusPill(
                          text: _humanize(
                            instance.status,
                          ),
                          color: statusColor,
                        ),
                        if (instance.isLegalHold)
                          _StatusPill(
                            text: 'Legal hold',
                            color: Theme.of(context).colorScheme.error,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_formatDateTime(instance.updatedAt ?? instance.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 58,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 58,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load hospital forms',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _templateIcon(String category) {
  switch (category) {
    case 'admission':
      return Icons.login;

    case 'consent_privacy':
      return Icons.privacy_tip_outlined;

    case 'emergency':
      return Icons.emergency_outlined;

    case 'theatre_preoperative':
      return Icons.medical_services_outlined;

    case 'nursing':
      return Icons.monitor_heart_outlined;

    case 'medication_administration':
      return Icons.medication_outlined;

    case 'pharmacy':
      return Icons.local_pharmacy_outlined;

    case 'laboratory':
      return Icons.science_outlined;

    case 'radiology_imaging':
      return Icons.image_outlined;

    case 'discharge':
      return Icons.logout;

    case 'transfer_referral':
      return Icons.transfer_within_a_station;

    default:
      return Icons.description_outlined;
  }
}

Color _classificationColor(
  BuildContext context,
  String classification,
) {
  final scheme = Theme.of(context).colorScheme;

  switch (classification) {
    case 'patient_visible':
      return scheme.primary;

    case 'clinical':
      return scheme.tertiary;

    case 'administrative':
      return scheme.secondary;

    case 'highly_restricted':
      return scheme.error;

    default:
      return scheme.primary;
  }
}

Color _statusColor(
  BuildContext context,
  String status,
) {
  final scheme = Theme.of(context).colorScheme;

  switch (status) {
    case 'draft':
      return scheme.secondary;

    case 'in_progress':
      return scheme.primary;

    case 'submitted':
    case 'under_review':
      return scheme.tertiary;

    case 'approved':
    case 'finalized':
      return Colors.green.shade700;

    case 'rejected':
    case 'void':
      return scheme.error;

    case 'amended':
      return Colors.orange.shade800;

    default:
      return scheme.primary;
  }
}

String _humanize(String value) {
  final clean = value
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  if (clean.isEmpty) {
    return '';
  }

  return clean.split(' ').map((word) {
    if (word.isEmpty) {
      return word;
    }

    return '${word[0].toUpperCase()}'
        '${word.substring(1).toLowerCase()}';
  }).join(' ');
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'Unknown date';
  }

  final local = value.toLocal();

  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _friendlyError(Object error) {
  if (error is HospitalFormEngineException) {
    return error.message;
  }

  final message = error.toString().trim();

  if (message.isEmpty) {
    return 'An unknown hospital form error occurred.';
  }

  return message;
}
