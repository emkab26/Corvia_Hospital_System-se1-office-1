import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/controlled_form_service.dart';

class ControlledFormMasterViewerPage extends StatefulWidget {
  const ControlledFormMasterViewerPage({
    super.key,
    required this.registry,
    required this.version,
  });

  final ControlledFormRegistryRecord registry;
  final ControlledFormVersionRecord version;

  @override
  State<ControlledFormMasterViewerPage> createState() =>
      _ControlledFormMasterViewerPageState();
}

class _ControlledFormMasterViewerPageState
    extends State<ControlledFormMasterViewerPage> {
  final ControlledFormService _service = ControlledFormService();

  bool _loading = true;
  bool _refreshing = false;

  String? _errorMessage;

  Uint8List? _pdfBytes;

  List<ControlledFormApprovalEvent> _events = [];

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load({
    bool refresh = false,
  }) async {
    if (refresh) {
      if (mounted) {
        setState(() {
          _refreshing = true;
          _errorMessage = null;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _loading = true;
          _errorMessage = null;
        });
      }
    }

    try {
      if (!widget.version.hasUploadedSource) {
        throw const ControlledFormException(
          'This controlled version does not have a completed '
          'official PDF upload yet.',
        );
      }

      final results = await Future.wait<dynamic>([
        _service.downloadOfficialPdf(
          version: widget.version,
        ),
        _service.loadApprovalEvents(
          versionId: widget.version.id,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _pdfBytes = results[0] as Uint8List;

        _events = results[1] as List<ControlledFormApprovalEvent>;

        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = _message(error);
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _message(
    Object error,
  ) {
    if (error is ControlledFormException) {
      return error.message;
    }

    return error.toString();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Controlled Master Review',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing
                ? null
                : () {
                    _load(
                      refresh: true,
                    );
                  },
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
          const SizedBox(
            width: 8,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final bytes = _pdfBytes;

    if (bytes == null || bytes.isEmpty) {
      return const Center(
        child: Text(
          'No controlled PDF data was loaded.',
        ),
      );
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        if (constraints.maxWidth >= 1050) {
          return _buildWideLayout(
            bytes,
          );
        }

        return _buildCompactLayout(
          bytes,
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'Controlled master could not be loaded',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(
              height: 10,
            ),
            Text(
              _errorMessage ?? 'Unknown error.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 18,
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

  Widget _buildWideLayout(
    Uint8List bytes,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 7,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: _buildPdfPreview(
              bytes,
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          color: Theme.of(context).dividerColor,
        ),
        Expanded(
          flex: 4,
          child: _buildSidePanel(),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(
    Uint8List bytes,
  ) {
    return ListView(
      padding: const EdgeInsets.all(
        16,
      ),
      children: [
        _buildStatusHeader(),
        const SizedBox(
          height: 16,
        ),
        SizedBox(
          height: 620,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              16,
            ),
            child: _buildPdfPreview(
              bytes,
            ),
          ),
        ),
        const SizedBox(
          height: 18,
        ),
        _buildDocumentDetailsCard(),
        const SizedBox(
          height: 18,
        ),
        _buildApprovalGatesCard(),
        const SizedBox(
          height: 18,
        ),
        _buildAuditHistoryCard(),
        const SizedBox(
          height: 32,
        ),
      ],
    );
  }

  Widget _buildSidePanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(
        18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusHeader(),
          const SizedBox(
            height: 18,
          ),
          _buildDocumentDetailsCard(),
          const SizedBox(
            height: 18,
          ),
          _buildApprovalGatesCard(),
          const SizedBox(
            height: 18,
          ),
          _buildAuditHistoryCard(),
          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildPdfPreview(
    Uint8List bytes,
  ) {
    return PdfPreview(
      build: (
        format,
      ) async {
        return bytes;
      },
      allowPrinting: false,
      allowSharing: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      useActions: false,
      dynamicLayout: false,
      pdfFileName: widget.version.sourceDocumentName ?? 'controlled_form.pdf',
      loadingWidget: const Center(
        child: CircularProgressIndicator(),
      ),
      onError: (
        context,
        error,
      ) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 46,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(
                  height: 12,
                ),
                const Text(
                  'PDF preview failed',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader() {
    final version = widget.version;

    final registry = widget.registry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: version.productionApproved
            ? Colors.green.withValues(
                alpha: 0.08,
              )
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: version.productionApproved
              ? Colors.green.withValues(
                  alpha: 0.35,
                )
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: version.productionApproved
                    ? Colors.green.withValues(
                        alpha: 0.15,
                      )
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  version.productionApproved
                      ? Icons.verified
                      : Icons.policy_outlined,
                  color: version.productionApproved
                      ? Colors.green
                      : Theme.of(context).colorScheme.primary,
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
                      registry.officialFormName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      'Version ${version.versionNumber} • '
                      '${version.versionLabel}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ViewerBadge(
                icon: Icons.flag_outlined,
                text: _pretty(
                  version.approvalStatus,
                ),
              ),
              _ViewerBadge(
                icon: Icons.fact_check_outlined,
                text: '${version.approvedGateCount}/7 gates',
              ),
              _ViewerBadge(
                icon: Icons.shield_outlined,
                text: registry.productionApproved
                    ? 'Registry Approved'
                    : 'Registry Not Approved',
              ),
              if (version.productionApproved)
                const _ViewerBadge(
                  icon: Icons.verified,
                  text: 'PRODUCTION APPROVED',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentDetailsCard() {
    final version = widget.version;

    final registry = widget.registry;

    return _ViewerSection(
      title: 'Controlled Master Details',
      icon: Icons.description_outlined,
      child: Column(
        children: [
          _ViewerDetailRow(
            label: 'Corvia code',
            value: registry.formCode,
          ),
          _ViewerDetailRow(
            label: 'Official form',
            value: registry.officialFormName,
          ),
          _ViewerDetailRow(
            label: 'Jurisdiction',
            value: registry.jurisdiction,
          ),
          _ViewerDetailRow(
            label: 'Source type',
            value: _pretty(
              registry.sourceType,
            ),
          ),
          _ViewerDetailRow(
            label: 'Issuing authority',
            value: _value(
              registry.issuingAuthority,
            ),
          ),
          _ViewerDetailRow(
            label: 'Official form number',
            value: _value(
              version.officialFormNumber,
            ),
          ),
          _ViewerDetailRow(
            label: 'Official version',
            value: _value(
              version.officialVersionReference,
            ),
          ),
          _ViewerDetailRow(
            label: 'Revision',
            value: _value(
              version.officialRevisionReference,
            ),
          ),
          _ViewerDetailRow(
            label: 'Effective date',
            value: _date(
              version.effectiveOn,
            ),
          ),
          _ViewerDetailRow(
            label: 'Retired date',
            value: _date(
              version.retiredOn,
            ),
          ),
          _ViewerDetailRow(
            label: 'File',
            value: _value(
              version.sourceDocumentName,
            ),
          ),
          _ViewerDetailRow(
            label: 'MIME type',
            value: _value(
              version.mimeType,
            ),
          ),
          _ViewerDetailRow(
            label: 'File size',
            value: _fileSize(
              version.fileSizeBytes,
            ),
          ),
          _ViewerDetailRow(
            label: 'Storage bucket',
            value: _value(
              version.storageBucket,
            ),
          ),
          _ViewerDetailRow(
            label: 'Production status',
            value: version.productionApproved
                ? 'Production Approved'
                : _pretty(
                    version.approvalStatus,
                  ),
          ),
          const SizedBox(
            height: 12,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SHA-256',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              10,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
            child: SelectableText(
              version.sha256 ?? 'No SHA-256 recorded',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalGatesCard() {
    final version = widget.version;

    return _ViewerSection(
      title: 'Production Approval Gates',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: ControlledFormReviewType.values.map(
          (
            type,
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
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(
                          alpha: 0.5,
                        ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    approved
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: approved ? Colors.green : null,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Text(
                      type.displayName,
                      style: TextStyle(
                        fontWeight:
                            approved ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    approved ? 'Approved' : 'Pending',
                    style: TextStyle(
                      color: approved
                          ? Colors.green
                          : Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  Widget _buildAuditHistoryCard() {
    return _ViewerSection(
      title: 'Approval Audit History',
      icon: Icons.history_outlined,
      child: _events.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 12,
              ),
              child: Center(
                child: Text(
                  'No approval events recorded yet.',
                ),
              ),
            )
          : Column(
              children: _events
                  .map(
                    _buildAuditEvent,
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildAuditEvent(
    ControlledFormApprovalEvent event,
  ) {
    final color = _eventColor(
      event,
    );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.10,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _eventIcon(
                event.eventType,
              ),
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(
                12,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(
                      alpha: 0.45,
                    ),
                borderRadius: BorderRadius.circular(
                  12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _eventTitle(
                            event,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Text(
                        _dateTime(
                          event.createdAt,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (event.reviewType != null) ...[
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      'Review: '
                      '${_pretty(event.reviewType!)}',
                    ),
                  ],
                  if (event.decision != null) ...[
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      'Decision: '
                      '${_pretty(event.decision!)}',
                    ),
                  ],
                  if (event.notes != null &&
                      event.notes!.trim().isNotEmpty) ...[
                    const SizedBox(
                      height: 7,
                    ),
                    Text(
                      event.notes!,
                    ),
                  ],
                  if (event.metadata.isNotEmpty) ...[
                    const SizedBox(
                      height: 9,
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Audit metadata',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface,
                            borderRadius: BorderRadius.circular(
                              8,
                            ),
                          ),
                          child: SelectableText(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(
                              event.metadata,
                            ),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
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

  Color _eventColor(
    ControlledFormApprovalEvent event,
  ) {
    final value = '${event.eventType} '
            '${event.decision ?? ''}'
        .toLowerCase();

    if (value.contains(
          'reject',
        ) ||
        value.contains(
          'rejection',
        )) {
      return Colors.red;
    }

    if (value.contains(
          'approve',
        ) ||
        value.contains(
          'verified',
        ) ||
        value.contains(
          'production',
        )) {
      return Colors.green;
    }

    if (value.contains(
      'retire',
    )) {
      return Colors.orange;
    }

    if (value.contains(
      'upload',
    )) {
      return Colors.blue;
    }

    return Theme.of(context).colorScheme.primary;
  }

  IconData _eventIcon(
    String eventType,
  ) {
    switch (eventType) {
      case 'version_created':
        return Icons.add_circle_outline;

      case 'source_uploaded':
        return Icons.upload_file_outlined;

      case 'source_verified':
        return Icons.verified_outlined;

      case 'layout_review':
        return Icons.picture_as_pdf_outlined;

      case 'clinical_review':
        return Icons.medical_services_outlined;

      case 'legal_review':
        return Icons.gavel_outlined;

      case 'privacy_review':
        return Icons.privacy_tip_outlined;

      case 'records_review':
        return Icons.inventory_2_outlined;

      case 'hospital_approval':
        return Icons.local_hospital_outlined;

      case 'production_approval':
        return Icons.verified;

      case 'rejection':
        return Icons.cancel_outlined;

      case 'retirement':
        return Icons.archive_outlined;

      case 'instance_bound':
        return Icons.link_outlined;

      case 'registry_created':
        return Icons.library_add_outlined;

      default:
        return Icons.history;
    }
  }

  String _eventTitle(
    ControlledFormApprovalEvent event,
  ) {
    switch (event.eventType) {
      case 'registry_created':
        return 'Controlled registry created';

      case 'version_created':
        return 'Controlled version created';

      case 'source_uploaded':
        return 'Official PDF uploaded';

      case 'source_verified':
        return 'Official source verified';

      case 'layout_review':
        return 'Exact layout review';

      case 'clinical_review':
        return 'Clinical review';

      case 'legal_review':
        return 'Legal review';

      case 'privacy_review':
        return 'Privacy / POPIA review';

      case 'records_review':
        return 'Records-management review';

      case 'hospital_approval':
        return 'Hospital approval';

      case 'production_approval':
        return 'Production approval';

      case 'rejection':
        return 'Review rejected';

      case 'retirement':
        return 'Controlled version retired';

      case 'instance_bound':
        return 'Master bound to patient form instance';

      default:
        return _pretty(
          event.eventType,
        );
    }
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

  static String _dateTime(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Unknown time';
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(
          2,
          '0',
        );

    final month = local.month.toString().padLeft(
          2,
          '0',
        );

    final hour = local.hour.toString().padLeft(
          2,
          '0',
        );

    final minute = local.minute.toString().padLeft(
          2,
          '0',
        );

    return '$day/$month/${local.year} '
        '$hour:$minute';
  }

  static String _fileSize(
    int? bytes,
  ) {
    if (bytes == null) {
      return 'Not recorded';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _pretty(
    String value,
  ) {
    if (value.trim().isEmpty) {
      return '—';
    }

    return value
        .replaceAll(
          '_',
          ' ',
        )
        .split(' ')
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
              '${word.substring(1)}',
        )
        .join(' ');
  }
}

class _ViewerSection extends StatelessWidget {
  const _ViewerSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          child,
        ],
      ),
    );
  }
}

class _ViewerDetailRow extends StatelessWidget {
  const _ViewerDetailRow({
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
        bottom: 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerBadge extends StatelessWidget {
  const _ViewerBadge({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
