import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../services/hospital_form_pdf_service.dart';
import '../../theme/app_theme.dart';

class HospitalFormPdfPreviewPage extends StatefulWidget {
  const HospitalFormPdfPreviewPage({
    super.key,
    required this.instanceId,
    this.title,
    this.patientVisibleOnly = false,
    this.requireReleasedToPatient = false,
  });

  final String instanceId;

  final String? title;

  /// When true, only patient-visible form fields are included.
  final bool patientVisibleOnly;

  /// When true, the form must be finalized and explicitly released
  /// to the patient before the PDF may be generated.
  final bool requireReleasedToPatient;

  @override
  State<HospitalFormPdfPreviewPage> createState() =>
      _HospitalFormPdfPreviewPageState();
}

class _HospitalFormPdfPreviewPageState
    extends State<HospitalFormPdfPreviewPage> {
  final HospitalFormPdfService _pdfService = HospitalFormPdfService();

  bool _loading = true;
  bool _printing = false;
  bool _sharing = false;
  bool _refreshing = false;

  String? _errorMessage;

  HospitalFormPdfDocumentData? _documentData;

  Uint8List? _pdfBytes;

  String _fileName = 'Corvia_Hospital_Form.pdf';

  @override
  void initState() {
    super.initState();

    _loadPdf();
  }

  Future<void> _loadPdf() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final documentData = await _pdfService.loadDocument(
        instanceId: widget.instanceId,
        patientVisibleOnly: widget.patientVisibleOnly,
        requireReleasedToPatient: widget.requireReleasedToPatient,
      );

      final pdfBytes = await _pdfService.buildPdfFromData(
        documentData,
      );

      final fileName = _pdfService.buildFileName(
        documentData,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _documentData = documentData;

        _pdfBytes = pdfBytes;

        _fileName = fileName;

        _loading = false;
      });
    } on HospitalFormPdfException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = _cleanError(
          error,
        );
      });
    }
  }

  Future<void> _refreshPdf() async {
    if (_refreshing || _loading) {
      return;
    }

    setState(() {
      _refreshing = true;
    });

    try {
      await _loadPdf();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _printPdf() async {
    if (_printing || _sharing || _pdfBytes == null || _documentData == null) {
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      await _pdfService.logExport(
        data: _documentData!,
        action: 'print',
        fileName: _fileName,
        byteSize: _pdfBytes!.lengthInBytes,
        destination: 'printer',
        reason: _documentData!.patientSafeMode
            ? 'Released patient hospital form print initiated '
                'from Corvia secure PDF preview.'
            : 'Hospital form print initiated from Corvia PDF preview.',
        strict: true,
      );

      if (!mounted) {
        return;
      }

      final printed = await Printing.layoutPdf(
        name: _fileName,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
        onLayout: (
          format,
        ) async {
          return _pdfBytes!;
        },
      );

      if (!mounted) {
        return;
      }

      if (!printed) {
        _showMessage(
          'Printing was cancelled. '
          'The print attempt remains recorded in the audit trail.',
          isWarning: true,
        );

        return;
      }

      _showMessage(
        'Hospital form sent to printer. '
        'The export was audit-recorded successfully.',
      );
    } on HospitalFormPdfException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Print blocked because the medical-record export '
        'audit could not be completed. '
        '${error.message}',
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not print the hospital form. '
        '${_cleanError(error)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  Future<void> _sharePdf() async {
    if (_sharing || _printing || _pdfBytes == null || _documentData == null) {
      return;
    }

    setState(() {
      _sharing = true;
    });

    try {
      await _pdfService.logExport(
        data: _documentData!,
        action: 'share_export',
        fileName: _fileName,
        byteSize: _pdfBytes!.lengthInBytes,
        destination: 'share_sheet',
        reason: _documentData!.patientSafeMode
            ? 'Released patient hospital form share/export '
                'initiated from Corvia secure PDF preview.'
            : 'Hospital form share/export initiated from '
                'Corvia PDF preview.',
        strict: true,
      );

      if (!mounted) {
        return;
      }

      final shared = await Printing.sharePdf(
        bytes: _pdfBytes!,
        filename: _fileName,
      );

      if (!mounted) {
        return;
      }

      if (!shared) {
        _showMessage(
          'Share / export was cancelled. '
          'The export attempt remains recorded in the audit trail.',
          isWarning: true,
        );

        return;
      }

      _showMessage(
        'Hospital form shared / exported. '
        'The export was audit-recorded successfully.',
      );
    } on HospitalFormPdfException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Share / export blocked because the medical-record '
        'audit could not be completed. '
        '${error.message}',
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Could not share or export the hospital form. '
        '${_cleanError(error)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
    bool isWarning = false,
  }) {
    if (!mounted) {
      return;
    }

    Color? backgroundColor;

    if (isError) {
      backgroundColor = CorviaColors.danger;
    } else if (isWarning) {
      backgroundColor = CorviaColors.warning;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _cleanError(
    Object error,
  ) {
    if (error is HospitalFormPdfException) {
      return error.message;
    }

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
  }

  String _formatDateTime(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not recorded';
    }

    final local = date.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateOnly(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not recorded';
    }

    final local = date.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  String _prettyStatus(
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

  @override
  Widget build(
    BuildContext context,
  ) {
    final documentData = _documentData;

    final pageTitle = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : documentData?.formTitle ?? 'Hospital Form PDF';

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Text(
          pageTitle,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh PDF',
            onPressed: _loading || _refreshing ? null : _refreshPdf,
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
          IconButton(
            tooltip: 'Print',
            onPressed: _canUsePdfActions ? _printPdf : null,
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.print_outlined,
                  ),
          ),
          IconButton(
            tooltip: 'Share / Export',
            onPressed: _canUsePdfActions ? _sharePdf : null,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.ios_share_outlined,
                  ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  bool get _canUsePdfActions {
    return !_loading &&
        !_refreshing &&
        !_printing &&
        !_sharing &&
        _pdfBytes != null &&
        _documentData != null;
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoadingState();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_pdfBytes == null || _documentData == null) {
      return _buildMissingPdfState();
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final isWide = constraints.maxWidth >= 900;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 330,
                child: _buildInformationSidebar(),
              ),
              VerticalDivider(
                width: 1,
                color: context.cDivider,
              ),
              Expanded(
                child: _buildPdfPreview(),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildCompactHeader(),
            Divider(
              height: 1,
              color: context.cDivider,
            ),
            Expanded(
              child: _buildPdfPreview(),
            ),
          ],
        );
      },
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
            height: 18,
          ),
          Text(
            'Building hospital form PDF...',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            'Loading form answers, patient details and signatures.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
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
            maxWidth: 560,
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
                  Icons.picture_as_pdf_outlined,
                  size: 58,
                  color: CorviaColors.danger,
                ),
                const SizedBox(
                  height: 16,
                ),
                Text(
                  'PDF could not be generated',
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
                  _errorMessage ?? 'Unknown PDF generation error.',
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
                    onPressed: _loadPdf,
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

  Widget _buildMissingPdfState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              color: context.cTextMuted,
              size: 54,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              'No PDF is available',
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Refresh the document and try again.',
              style: TextStyle(
                color: context.cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfPreview() {
    final bytes = _pdfBytes;

    if (bytes == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: context.cBgPrimary,
      child: PdfPreview(
        build: (
          format,
        ) async {
          return bytes;
        },
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName: _fileName,

        /*
         * Built-in package export actions remain disabled.
         *
         * Every print/share action must pass through Corvia's
         * strict medical-record export audit.
         */
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        loadingWidget: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    final data = _documentData!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        14,
      ),
      color: context.cBgSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                ),
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: context.cAccentReadable,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.formTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      '${data.patientName} • ${data.hospitalName}',
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
          if (data.patientSafeMode) ...[
            const SizedBox(
              height: 10,
            ),
            _buildPatientSafeBanner(),
          ],
          if (!data.patientSafeMode &&
              (!data.isProductionReady || data.officialLayoutRequired)) ...[
            const SizedBox(
              height: 10,
            ),
            _buildApprovalBanner(
              compact: true,
            ),
          ],
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _canUsePdfActions ? _printPdf : null,
                  icon: _printing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.print_outlined,
                        ),
                  label: const Text(
                    'Print',
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _canUsePdfActions ? _sharePdf : null,
                  icon: _sharing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.ios_share_outlined,
                        ),
                  label: const Text(
                    'Share / Export',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInformationSidebar() {
    final data = _documentData!;

    return Container(
      color: context.cBgSecondary,
      child: ListView(
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.cAccentReadable.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                16,
              ),
            ),
            child: Icon(
              Icons.picture_as_pdf_outlined,
              color: context.cAccentReadable,
              size: 28,
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            data.formTitle,
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
            data.description,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          if (data.patientSafeMode) _buildPatientSafeBanner(),
          if (data.patientSafeMode)
            const SizedBox(
              height: 16,
            ),
          if (!data.patientSafeMode &&
              (!data.isProductionReady || data.officialLayoutRequired))
            _buildApprovalBanner(
              compact: false,
            ),
          if (!data.patientSafeMode &&
              (!data.isProductionReady || data.officialLayoutRequired))
            const SizedBox(
              height: 16,
            ),
          if (data.isControlledForm) ...[
            _buildControlledMasterSidebar(
              data,
            ),
            const SizedBox(
              height: 14,
            ),
          ],
          _buildInfoSection(
            title: 'Document',
            children: [
              _SidebarDetail(
                label: 'Category',
                value: data.category,
              ),
              _SidebarDetail(
                label: 'Status',
                value: _prettyStatus(
                  data.status,
                ),
              ),
              _SidebarDetail(
                label: 'Version',
                value: data.versionLabel,
              ),
              if (data.formCode.isNotEmpty)
                _SidebarDetail(
                  label: 'Form code',
                  value: data.formCode,
                ),
              _SidebarDetail(
                label: 'Classification',
                value: data.documentClassification,
              ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          _buildInfoSection(
            title: 'Patient',
            children: [
              _SidebarDetail(
                label: 'Name',
                value: data.patientName,
              ),
              _SidebarDetail(
                label: 'Patient number',
                value: data.patientNumber,
              ),
              if (data.patientIdNumber.isNotEmpty)
                _SidebarDetail(
                  label: 'ID number',
                  value: data.patientIdNumber,
                ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          _buildInfoSection(
            title: 'Hospital',
            children: [
              _SidebarDetail(
                label: 'Hospital',
                value: data.hospitalName,
              ),
              if (data.wardName.isNotEmpty)
                _SidebarDetail(
                  label: 'Ward',
                  value: data.wardName,
                ),
              if (data.roomName.isNotEmpty)
                _SidebarDetail(
                  label: 'Room',
                  value: data.roomName,
                ),
              if (data.bedName.isNotEmpty)
                _SidebarDetail(
                  label: 'Bed',
                  value: data.bedName,
                ),
            ],
          ),
          const SizedBox(
            height: 14,
          ),
          _buildInfoSection(
            title: 'Record',
            children: [
              _SidebarDetail(
                label: 'Created',
                value: _formatDateTime(
                  data.createdAt,
                ),
              ),
              _SidebarDetail(
                label: 'Submitted',
                value: _formatDateTime(
                  data.submittedAt,
                ),
              ),
              _SidebarDetail(
                label: 'Finalized',
                value: _formatDateTime(
                  data.finalizedAt,
                ),
              ),
              _SidebarDetail(
                label: 'Released',
                value: _formatDateTime(
                  data.releasedToPatientAt,
                ),
              ),
              _SidebarDetail(
                label: 'Signatures',
                value: data.signatures.length.toString(),
              ),
            ],
          ),
          const SizedBox(
            height: 18,
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _canUsePdfActions ? _printPdf : null,
              icon: _printing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.print_outlined,
                    ),
              label: const Text(
                'Print',
              ),
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canUsePdfActions ? _sharePdf : null,
              icon: _sharing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.ios_share_outlined,
                    ),
              label: const Text(
                'Share / Export',
              ),
            ),
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            _fileName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSafeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        11,
      ),
      decoration: BoxDecoration(
        color: CorviaColors.success.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
        border: Border.all(
          color: CorviaColors.success.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_person_outlined,
            color: CorviaColors.success,
            size: 20,
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Patient Copy',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  'Only patient-visible form content and safe official '
                  'document verification information are included.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 10.5,
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

  Widget _buildControlledMasterSidebar(
    HospitalFormPdfDocumentData data,
  ) {
    final controlled = data.controlledBindingEvidence;

    if (controlled == null || !controlled.isControlledForm) {
      return const SizedBox.shrink();
    }

    if (data.patientSafeMode) {
      return _buildPatientOfficialVerificationSidebar(
        controlled,
      );
    }

    final bound = controlled.isBound;

    final color = bound && controlled.verified
        ? CorviaColors.success
        : CorviaColors.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bound && controlled.verified
                    ? Icons.verified_user_outlined
                    : Icons.policy_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  bound && controlled.verified
                      ? 'Official Master Bound'
                      : 'Controlled Master Missing',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          _SidebarDetail(
            label: 'Official form',
            value: controlled.officialFormName.isNotEmpty
                ? controlled.officialFormName
                : controlled.formCode,
          ),
          if (bound) ...[
            _SidebarDetail(
              label: 'Master version',
              value: '${controlled.versionNumber ?? '-'}'
                  '${controlled.versionLabel.isNotEmpty ? ' • ${controlled.versionLabel}' : ''}',
            ),
            if (controlled.officialFormNumber.isNotEmpty)
              _SidebarDetail(
                label: 'Official form number',
                value: controlled.officialFormNumber,
              ),
            if (controlled.bindingId.isNotEmpty)
              _SidebarDetail(
                label: 'Binding ID',
                value: controlled.bindingId,
              ),
            if (controlled.sha256.isNotEmpty)
              _SidebarDetail(
                label: 'Master SHA-256',
                value: controlled.sha256,
              ),
          ] else
            const _SidebarDetail(
              label: 'Status',
              value: 'No immutable approved master binding',
            ),
        ],
      ),
    );
  }

  Widget _buildPatientOfficialVerificationSidebar(
    HospitalFormPdfControlledBindingEvidence controlled,
  ) {
    final verified = controlled.verified &&
        controlled.isBound &&
        controlled.productionApproved;

    final color = verified ? CorviaColors.success : CorviaColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                verified
                    ? Icons.verified_outlined
                    : Icons.warning_amber_rounded,
                color: color,
                size: 21,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  verified
                      ? 'Official Document Verified'
                      : 'Verification Unavailable',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          _SidebarDetail(
            label: 'Official form',
            value: controlled.officialFormName.isNotEmpty
                ? controlled.officialFormName
                : controlled.formCode,
          ),
          if (controlled.officialFormNumber.isNotEmpty)
            _SidebarDetail(
              label: 'Official form number',
              value: controlled.officialFormNumber,
            ),
          if (controlled.versionNumber != null ||
              controlled.versionLabel.isNotEmpty)
            _SidebarDetail(
              label: 'Version',
              value: '${controlled.versionNumber ?? '-'}'
                  '${controlled.versionLabel.isNotEmpty ? ' • ${controlled.versionLabel}' : ''}',
            ),
          if (controlled.officialVersionReference.isNotEmpty)
            _SidebarDetail(
              label: 'Official version',
              value: controlled.officialVersionReference,
            ),
          if (controlled.officialRevisionReference.isNotEmpty)
            _SidebarDetail(
              label: 'Revision',
              value: controlled.officialRevisionReference,
            ),
          if (controlled.effectiveOn != null)
            _SidebarDetail(
              label: 'Effective date',
              value: _formatDateOnly(
                controlled.effectiveOn,
              ),
            ),
          const SizedBox(
            height: 2,
          ),
          Text(
            verified
                ? 'Verified against the hospital\'s '
                    'production-approved official master.'
                : 'Contact the hospital if you require '
                    'an official statutory copy.',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner({
    required bool compact,
  }) {
    final data = _documentData!;

    final officialLayout = data.officialLayoutRequired;

    final productionReady = data.isProductionReady;

    final color = officialLayout ? CorviaColors.danger : CorviaColors.warning;

    String title;
    String message;

    if (officialLayout) {
      title = 'Official Layout Required';

      message = 'This preview is a Corvia record summary. '
          'An approved official layout is required for statutory '
          'or external submission.';
    } else if (!productionReady) {
      title = data.demoOnly ? 'Demo Form' : 'Not Production Approved';

      message = 'This template is not currently marked as an approved '
          'production hospital document.';
    } else {
      title = 'Production Approved';

      message = 'This form version is marked as production approved.';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.09,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.28,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            officialLayout ? Icons.gavel_outlined : Icons.warning_amber_rounded,
            color: color,
            size: compact ? 19 : 22,
          ),
          const SizedBox(
            width: 9,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 12 : 13,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  message,
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: compact ? 10 : 11,
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

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        13,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          15,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SidebarDetail extends StatelessWidget {
  const _SidebarDetail({
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.cTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          SelectableText(
            value,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
