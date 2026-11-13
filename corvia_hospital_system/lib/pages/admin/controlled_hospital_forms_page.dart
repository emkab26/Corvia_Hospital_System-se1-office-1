import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/controlled_form_service.dart';
import 'controlled_form_render_mapping_page.dart';

class ControlledHospitalFormsPage extends StatefulWidget {
  const ControlledHospitalFormsPage({
    super.key,
    required this.hospitalId,
  });

  final String hospitalId;

  @override
  State<ControlledHospitalFormsPage> createState() =>
      _ControlledHospitalFormsPageState();
}

class _ControlledHospitalFormsPageState
    extends State<ControlledHospitalFormsPage> {
  final ControlledFormService _service = ControlledFormService();

  bool _loading = true;
  bool _working = false;

  String? _errorMessage;

  List<ControlledFormRegistryRecord> _registry = [];
  List<ControlledFormVersionRecord> _versions = [];

  ControlledFormDashboardStats? _stats;

  String _search = '';

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _service.loadRegistry(
          hospitalId: widget.hospitalId,
        ),
        _service.loadHospitalVersions(
          hospitalId: widget.hospitalId,
        ),
        _service.loadDashboardStats(
          hospitalId: widget.hospitalId,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _registry = results[0] as List<ControlledFormRegistryRecord>;

        _versions = results[1] as List<ControlledFormVersionRecord>;

        _stats = results[2] as ControlledFormDashboardStats;

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = _message(error);
        _loading = false;
      });
    }
  }

  List<ControlledFormVersionRecord> _versionsFor(
    String registryId,
  ) {
    final result = _versions
        .where(
          (version) => version.registryId == registryId,
        )
        .toList();

    result.sort(
      (a, b) => b.versionNumber.compareTo(a.versionNumber),
    );

    return result;
  }

  List<ControlledFormRegistryRecord> get _filteredRegistry {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return _registry;
    }

    return _registry.where(
      (item) {
        return item.officialFormName.toLowerCase().contains(query) ||
            item.formCode.toLowerCase().contains(query) ||
            item.sourceType.toLowerCase().contains(query) ||
            (item.issuingAuthority ?? '').toLowerCase().contains(query);
      },
    ).toList();
  }

  Future<void> _upload(
    ControlledFormRegistryRecord registry,
  ) async {
    final draft = await showDialog<_ControlledUploadDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _ControlledUploadDialog(
          formName: registry.officialFormName,
        );
      },
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      final result = await _service.uploadOfficialPdf(
        registryId: registry.id,
        versionLabel: draft.versionLabel,
        originalFileName: draft.fileName,
        bytes: draft.bytes,
        officialFormNumber: draft.officialFormNumber,
        officialVersionReference: draft.officialVersionReference,
        officialRevisionReference: draft.officialRevisionReference,
        effectiveOn: draft.effectiveOn,
        notes: draft.notes,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Official PDF uploaded. Version '
        '${result.versionNumber ?? ''} is ready for review.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        _message(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _approveGate(
    ControlledFormVersionRecord version,
    ControlledFormReviewType type,
  ) async {
    final notes = await _notesDialog(
      title: type.displayName,
      message: 'Confirm that this controlled master passed '
          '${type.displayName}.',
      confirmLabel: 'Approve Gate',
    );

    if (notes == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await _service.approveReviewGate(
        versionId: version.id,
        reviewType: type,
        notes: notes,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        '${type.displayName} approved.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        _message(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _rejectGate(
    ControlledFormVersionRecord version,
    ControlledFormReviewType type,
  ) async {
    final reason = await _notesDialog(
      title: 'Reject ${type.displayName}',
      message: 'Enter the reason this controlled master '
          'failed the review.',
      confirmLabel: 'Reject',
      reasonRequired: true,
    );

    if (reason == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await _service.rejectReviewGate(
        versionId: version.id,
        reviewType: type,
        reason: reason,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        '${type.displayName} rejected.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        _message(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _productionApprove(
    ControlledFormVersionRecord version,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Production Approval',
          ),
          content: const Text(
            'This will mark this exact controlled master '
            'as the current production-approved version.\n\n'
            'Any previous production master will be retired.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              icon: const Icon(
                Icons.verified_outlined,
              ),
              label: const Text(
                'Approve Production',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await _service.approveForProduction(
        versionId: version.id,
        notes: 'Approved through Corvia Controlled Forms Admin.',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Controlled master is now production approved.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        _message(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _retire(
    ControlledFormVersionRecord version,
  ) async {
    final reason = await _notesDialog(
      title: 'Retire Version',
      message: 'Enter a reason for retiring '
          '${version.versionLabel}.',
      confirmLabel: 'Retire',
      reasonRequired: true,
    );

    if (reason == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await _service.retireVersion(
        versionId: version.id,
        reason: reason,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Controlled master retired.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        _message(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ==========================================================
  // CONTROLLED PDF MAPPING
  // ==========================================================

  Future<void> _openPdfMapping(
    ControlledFormRegistryRecord registry,
    ControlledFormVersionRecord version,
  ) async {
    if (_working) {
      return;
    }

    if (!version.hasUploadedSource) {
      _showError(
        'Upload and finalise the official PDF master before '
        'creating its exact render mapping.',
      );

      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return ControlledFormRenderMappingPage(
            registry: registry,
            version: version,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    /*
     * Reload after returning because the admin may have created,
     * submitted, approved or retired a render mapping.
     */
    await _load();
  }

  Future<String?> _notesDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool reasonRequired = false,
  }) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String? validationMessage;

        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(
                      height: 16,
                    ),
                    TextField(
                      controller: controller,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: reasonRequired ? 'Reason' : 'Review notes',
                        border: const OutlineInputBorder(),
                        errorText: validationMessage,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                    );
                  },
                  child: const Text(
                    'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();

                    if (reasonRequired && value.isEmpty) {
                      setDialogState(() {
                        validationMessage = 'A reason is required.';
                      });

                      return;
                    }

                    Navigator.pop(
                      context,
                      value,
                    );
                  },
                  child: Text(
                    confirmLabel,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    return result;
  }

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  void _showError(
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  String _message(Object error) {
    if (error is ControlledFormException) {
      return error.message;
    }

    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Controlled Official Forms',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _working ? null : _load,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
          const SizedBox(
            width: 8,
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_working)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: 0.08,
                ),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
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
                size: 48,
              ),
              const SizedBox(
                height: 16,
              ),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(
                height: 16,
              ),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Retry',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(
          20,
        ),
        children: [
          _buildHeader(),
          const SizedBox(
            height: 20,
          ),
          _buildStats(),
          const SizedBox(
            height: 20,
          ),
          _buildSearch(),
          const SizedBox(
            height: 16,
          ),
          if (_filteredRegistry.isEmpty)
            _buildEmptyState()
          else
            ..._filteredRegistry.map(
              _buildRegistryCard,
            ),
          const SizedBox(
            height: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              child: Icon(
                Icons.policy_outlined,
              ),
            ),
            const SizedBox(
              width: 16,
            ),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official Form Control',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(
                    height: 6,
                  ),
                  Text(
                    'Upload exact controlled PDFs, verify their '
                    'versions and move them through source, layout, '
                    'clinical, legal, privacy, records and hospital '
                    'approval before production use.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final stats = _stats;

    if (stats == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width = constraints.maxWidth;

        final cardWidth = width >= 1000
            ? (width - 48) / 4
            : width >= 600
                ? (width - 16) / 2
                : width;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(
              width: cardWidth,
              label: 'Controlled Forms',
              value: stats.controlledForms,
              icon: Icons.description_outlined,
            ),
            _StatCard(
              width: cardWidth,
              label: 'Master Versions',
              value: stats.masterVersions,
              icon: Icons.history_outlined,
            ),
            _StatCard(
              width: cardWidth,
              label: 'Under Review',
              value: stats.underReview,
              icon: Icons.fact_check_outlined,
            ),
            _StatCard(
              width: cardWidth,
              label: 'Production Approved',
              value: stats.productionApproved,
              icon: Icons.verified_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearch() {
    return TextField(
      onChanged: (value) {
        setState(() {
          _search = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Search J88, W.Cl.4, NMC, DHA-1663...',
        prefixIcon: const Icon(
          Icons.search,
        ),
        border: const OutlineInputBorder(),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  setState(() {
                    _search = '';
                  });
                },
                icon: const Icon(
                  Icons.close,
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(
          32,
        ),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 48,
            ),
            SizedBox(
              height: 12,
            ),
            Text(
              'No controlled forms match this search.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistryCard(
    ControlledFormRegistryRecord registry,
  ) {
    final versions = _versionsFor(registry.id);

    final latest = versions.isEmpty ? null : versions.first;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            registry.productionApproved
                ? Icons.verified
                : Icons.description_outlined,
          ),
        ),
        title: Text(
          registry.officialFormName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(
            top: 6,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Badge(
                text: registry.formCode,
              ),
              _Badge(
                text: _pretty(
                  registry.sourceType,
                ),
              ),
              _Badge(
                text: _pretty(
                  registry.productionStatus,
                ),
              ),
              if (registry.requiresExternalSubmission)
                const _Badge(
                  text: 'External Submission',
                ),
            ],
          ),
        ),
        trailing: FilledButton.icon(
          onPressed: _working
              ? null
              : () {
                  _upload(
                    registry,
                  );
                },
          icon: const Icon(
            Icons.upload_file_outlined,
          ),
          label: Text(
            latest == null ? 'Upload Official PDF' : 'New Version',
          ),
        ),
        children: [
          const Divider(
            height: 1,
          ),
          Padding(
            padding: const EdgeInsets.all(
              18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRegistryMetadata(
                  registry,
                ),
                const SizedBox(
                  height: 18,
                ),
                if (versions.isEmpty)
                  _buildNoVersion(
                    registry,
                  )
                else
                  ...versions.map(
                    (version) => _buildVersionCard(
                      registry,
                      version,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistryMetadata(
    ControlledFormRegistryRecord registry,
  ) {
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _Meta(
          label: 'Jurisdiction',
          value: registry.jurisdiction,
        ),
        _Meta(
          label: 'Source Type',
          value: _pretty(
            registry.sourceType,
          ),
        ),
        _Meta(
          label: 'Official Layout',
          value: registry.requiresOfficialLayout ? 'Required' : 'Not Required',
        ),
        _Meta(
          label: 'External Submission',
          value: registry.requiresExternalSubmission ? 'Yes' : 'No',
        ),
        _Meta(
          label: 'Production',
          value: registry.productionApproved ? 'Approved' : 'Not Approved',
        ),
      ],
    );
  }

  Widget _buildNoVersion(
    ControlledFormRegistryRecord registry,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_upload_outlined,
            size: 42,
          ),
          const SizedBox(
            height: 10,
          ),
          const Text(
            'No official master PDF uploaded yet.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          const Text(
            'This form remains blocked from production approval.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(
            height: 14,
          ),
          FilledButton.icon(
            onPressed: _working
                ? null
                : () {
                    _upload(
                      registry,
                    );
                  },
            icon: const Icon(
              Icons.upload_file,
            ),
            label: const Text(
              'Upload Official PDF',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionCard(
    ControlledFormRegistryRecord registry,
    ControlledFormVersionRecord version,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: version.productionApproved
              ? Colors.green.withValues(
                  alpha: 0.55,
                )
              : Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(
          14,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Version ${version.versionNumber} — '
                      '${version.versionLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Badge(
                          text: _pretty(
                            version.approvalStatus,
                          ),
                        ),
                        _Badge(
                          text: '${version.approvedGateCount}/7 Review Gates',
                        ),
                        if (version.productionApproved)
                          const _Badge(
                            text: 'PRODUCTION APPROVED',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Meta(
                label: 'Official Form No.',
                value: _value(
                  version.officialFormNumber,
                ),
              ),
              _Meta(
                label: 'Official Version',
                value: _value(
                  version.officialVersionReference,
                ),
              ),
              _Meta(
                label: 'Revision',
                value: _value(
                  version.officialRevisionReference,
                ),
              ),
              _Meta(
                label: 'Effective Date',
                value: _date(
                  version.effectiveOn,
                ),
              ),
              _Meta(
                label: 'File',
                value: _value(
                  version.sourceDocumentName,
                ),
              ),
              _Meta(
                label: 'Size',
                value: _fileSize(
                  version.fileSizeBytes,
                ),
              ),
            ],
          ),
          if (version.sha256 != null && version.sha256!.isNotEmpty) ...[
            const SizedBox(
              height: 14,
            ),
            SelectableText(
              'SHA-256: ${version.sha256}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (version.rejectionReason != null) ...[
            const SizedBox(
              height: 14,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                12,
              ),
              decoration: BoxDecoration(
                color: Colors.red.withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Text(
                'Rejected: '
                '${version.rejectionReason}',
              ),
            ),
          ],
          const SizedBox(
            height: 20,
          ),
          const Text(
            'Production Review Gates',
            style: TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          ...ControlledFormReviewType.values.map(
            (type) => _buildGate(
              version,
              type,
            ),
          ),
          const SizedBox(
            height: 18,
          ),

          // ==================================================
          // OFFICIAL MASTER ACTIONS
          // ==================================================

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _working || !version.hasUploadedSource
                    ? null
                    : () {
                        _openPdfMapping(
                          registry,
                          version,
                        );
                      },
                icon: const Icon(
                  Icons.design_services_outlined,
                ),
                label: const Text(
                  'PDF Mapping',
                ),
              ),
              if (!version.productionApproved && version.allReviewGatesApproved)
                FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () {
                          _productionApprove(
                            version,
                          );
                        },
                  icon: const Icon(
                    Icons.verified_outlined,
                  ),
                  label: const Text(
                    'Production Approve',
                  ),
                ),
              if (version.approvalStatus != 'retired')
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () {
                          _retire(
                            version,
                          );
                        },
                  icon: const Icon(
                    Icons.archive_outlined,
                  ),
                  label: const Text(
                    'Retire Version',
                  ),
                ),
            ],
          ),

          if (!version.hasUploadedSource) ...[
            const SizedBox(
              height: 8,
            ),
            Text(
              'PDF Mapping becomes available after the '
              'official master PDF has been securely uploaded '
              'and finalised.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGate(
    ControlledFormVersionRecord version,
    ControlledFormReviewType type,
  ) {
    final approved = version.reviewApproved(
      type,
    );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: approved
            ? Colors.green.withValues(
                alpha: 0.08,
              )
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
        borderRadius: BorderRadius.circular(
          10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.check_circle : Icons.radio_button_unchecked,
            color: approved ? Colors.green : null,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              type.displayName,
              style: TextStyle(
                fontWeight: approved ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (!approved &&
              version.approvalStatus != 'retired' &&
              !version.productionApproved) ...[
            TextButton(
              onPressed: _working
                  ? null
                  : () {
                      _rejectGate(
                        version,
                        type,
                      );
                    },
              child: const Text(
                'Reject',
              ),
            ),
            FilledButton(
              onPressed: _working
                  ? null
                  : () {
                      _approveGate(
                        version,
                        type,
                      );
                    },
              child: const Text(
                'Approve',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _pretty(
    String value,
  ) {
    if (value.trim().isEmpty) {
      return '—';
    }

    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  static String _value(
    String? value,
  ) {
    if (value == null || value.trim().isEmpty) {
      return 'Not set';
    }

    return value;
  }

  static String _date(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not set';
    }

    final day = date.day.toString().padLeft(
          2,
          '0',
        );

    final month = date.month.toString().padLeft(
          2,
          '0',
        );

    return '$day/$month/${date.year}';
  }

  static String _fileSize(
    int? bytes,
  ) {
    if (bytes == null) {
      return 'Not uploaded';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ============================================================
// UPLOAD DIALOG
// ============================================================

class _ControlledUploadDialog extends StatefulWidget {
  const _ControlledUploadDialog({
    required this.formName,
  });

  final String formName;

  @override
  State<_ControlledUploadDialog> createState() =>
      _ControlledUploadDialogState();
}

class _ControlledUploadDialogState extends State<_ControlledUploadDialog> {
  final TextEditingController _versionLabelController = TextEditingController();

  final TextEditingController _formNumberController = TextEditingController();

  final TextEditingController _officialVersionController =
      TextEditingController();

  final TextEditingController _revisionController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  Uint8List? _bytes;
  String? _fileName;

  DateTime? _effectiveOn;

  bool _picking = false;

  @override
  void dispose() {
    _versionLabelController.dispose();
    _formNumberController.dispose();
    _officialVersionController.dispose();
    _revisionController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  Future<void> _pickPdf() async {
    setState(() {
      _picking = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
        ],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      final bytes = file.bytes;

      if (bytes == null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read the selected PDF bytes.',
            ),
          ),
        );

        return;
      }

      if (bytes.length > 26214400) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The PDF is larger than 25 MB.',
            ),
          ),
        );

        return;
      }

      setState(() {
        _bytes = bytes;
        _fileName = file.name;
      });
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  Future<void> _pickEffectiveDate() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveOn ?? now,
      firstDate: DateTime(
        1990,
      ),
      lastDate: DateTime(
        now.year + 20,
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _effectiveOn = selected;
    });
  }

  void _submit() {
    final versionLabel = _versionLabelController.text.trim();

    if (versionLabel.isEmpty) {
      _showError(
        'Version label is required.',
      );

      return;
    }

    if (_fileName == null || _bytes == null) {
      _showError(
        'Select the official PDF first.',
      );

      return;
    }

    Navigator.pop(
      context,
      _ControlledUploadDraft(
        versionLabel: versionLabel,
        fileName: _fileName!,
        bytes: _bytes!,
        officialFormNumber: _formNumberController.text.trim(),
        officialVersionReference: _officialVersionController.text.trim(),
        officialRevisionReference: _revisionController.text.trim(),
        effectiveOn: _effectiveOn,
        notes: _notesController.text.trim(),
      ),
    );
  }

  void _showError(
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Upload Official Master\n'
        '${widget.formName}',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _versionLabelController,
                decoration: const InputDecoration(
                  labelText: 'Version label *',
                  hintText: 'Example: Official 2026 Revision 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _formNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Official form number',
                        hintText: 'Example: J88',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _officialVersionController,
                      decoration: const InputDecoration(
                        labelText: 'Official version reference',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 14,
              ),
              TextField(
                controller: _revisionController,
                decoration: const InputDecoration(
                  labelText: 'Official revision reference',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              InkWell(
                onTap: _pickEffectiveDate,
                borderRadius: BorderRadius.circular(
                  10,
                ),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Effective date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(
                      Icons.calendar_month_outlined,
                    ),
                  ),
                  child: Text(
                    _effectiveOn == null
                        ? 'Not set'
                        : '${_effectiveOn!.day.toString().padLeft(2, '0')}/'
                            '${_effectiveOn!.month.toString().padLeft(2, '0')}/'
                            '${_effectiveOn!.year}',
                  ),
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Source / approval notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(
                  16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _fileName == null
                          ? Icons.picture_as_pdf_outlined
                          : Icons.check_circle_outline,
                      size: 40,
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      _fileName ?? 'No official PDF selected',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_bytes != null) ...[
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        '${(_bytes!.length / (1024 * 1024)).toStringAsFixed(2)} MB',
                      ),
                    ],
                    const SizedBox(
                      height: 12,
                    ),
                    OutlinedButton.icon(
                      onPressed: _picking ? null : _pickPdf,
                      icon: _picking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.upload_file_outlined,
                            ),
                      label: Text(
                        _fileName == null
                            ? 'Select Official PDF'
                            : 'Choose Different PDF',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              const Text(
                'The uploaded file will remain non-production '
                'until every controlled approval gate passes.',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
            );
          },
          child: const Text(
            'Cancel',
          ),
        ),
        FilledButton.icon(
          onPressed: _picking ? null : _submit,
          icon: const Icon(
            Icons.lock_outline,
          ),
          label: const Text(
            'Upload Controlled Master',
          ),
        ),
      ],
    );
  }
}

// ============================================================
// UPLOAD DRAFT
// ============================================================

class _ControlledUploadDraft {
  const _ControlledUploadDraft({
    required this.versionLabel,
    required this.fileName,
    required this.bytes,
    this.officialFormNumber,
    this.officialVersionReference,
    this.officialRevisionReference,
    this.effectiveOn,
    this.notes,
  });

  final String versionLabel;

  final String fileName;
  final Uint8List bytes;

  final String? officialFormNumber;
  final String? officialVersionReference;
  final String? officialRevisionReference;

  final DateTime? effectiveOn;

  final String? notes;
}

// ============================================================
// SMALL UI WIDGETS
// ============================================================

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(
            18,
          ),
          child: Row(
            children: [
              CircleAvatar(
                child: Icon(
                  icon,
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
                      '$value',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          999,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
