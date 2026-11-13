import 'package:flutter/material.dart';

import '../../services/interhospital_transfer_service.dart';
import '../../services/transfer_document_picker_service.dart';
import '../../theme/app_theme.dart';

class InterhospitalTransferDocumentUploadPage extends StatefulWidget {
  const InterhospitalTransferDocumentUploadPage({
    super.key,
    required this.transfer,
    required this.hospitalId,
  });

  final InterhospitalTransferRecord transfer;
  final String hospitalId;

  @override
  State<InterhospitalTransferDocumentUploadPage> createState() =>
      _InterhospitalTransferDocumentUploadPageState();
}

class _InterhospitalTransferDocumentUploadPageState
    extends State<InterhospitalTransferDocumentUploadPage> {
  final InterhospitalTransferService _transferService =
      InterhospitalTransferService();

  final TransferDocumentPickerService _pickerService =
      TransferDocumentPickerService();

  final TextEditingController _descriptionController = TextEditingController();

  TransferPickedDocument? _selectedDocument;

  bool _picking = false;
  bool _uploading = false;

  bool _isClinical = true;
  bool _sharedWithDestination = true;

  double _uploadProgress = 0;
  String _uploadStatus = '';

  String _documentType = 'clinical_handover';

  static const List<String> _documentTypes = [
    'clinical_handover',
    'referral_letter',
    'medical_history',
    'medication_list',
    'laboratory_result',
    'radiology_result',
    'consent_form',
    'discharge_summary',
    'transport_document',
    'identity_document',
    'other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  String _humanize(String value) {
    final words = value.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));

    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }

      return '${word[0].toUpperCase()}'
          '${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CorviaColors.danger : CorviaColors.accentDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickDocument() async {
    if (_picking || _uploading) {
      return;
    }

    setState(() {
      _picking = true;
    });

    try {
      final document = await _pickerService.pickDocument();

      if (document == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDocument = document;
        _uploadProgress = 0;
        _uploadStatus = '';
      });
    } catch (error) {
      _showMessage(
        'Document could not be selected: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  Future<void> _uploadDocument() async {
    final document = _selectedDocument;

    if (document == null) {
      _showMessage(
        'Select a document first.',
        error: true,
      );
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0.15;
      _uploadStatus = 'Validating document...';
    });

    try {
      await Future<void>.delayed(
        const Duration(milliseconds: 150),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _uploadProgress = 0.35;
        _uploadStatus = 'Preparing secure storage path...';
      });

      await Future<void>.delayed(
        const Duration(milliseconds: 150),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _uploadProgress = 0.60;
        _uploadStatus = 'Uploading encrypted transfer document...';
      });

      final uploadedDocument = await _transferService.uploadTransferDocument(
        transferId: widget.transfer.transferId,
        hospitalId: widget.hospitalId,
        bytes: document.bytes,
        fileName: document.fileName,
        documentType: _documentType,
        mimeType: document.mimeType,
        description: _descriptionController.text.trim(),
        isClinical: _isClinical,
        sharedWithDestination: _sharedWithDestination,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _uploadProgress = 1;
        _uploadStatus = 'Document uploaded successfully.';
      });

      _showMessage(
        '${uploadedDocument.fileName} uploaded successfully.',
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 500),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        uploadedDocument,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _uploadProgress = 0;
        _uploadStatus = '';
      });

      _showMessage(
        'Document upload failed: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  IconData _documentIcon(
    TransferPickedDocument document,
  ) {
    if (document.isPdf) {
      return Icons.picture_as_pdf_rounded;
    }

    if (document.isImage) {
      return Icons.image_rounded;
    }

    if (document.isDicom) {
      return Icons.monitor_heart_rounded;
    }

    if (document.isWordDocument) {
      return Icons.description_rounded;
    }

    if (document.isSpreadsheet) {
      return Icons.table_chart_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Color _documentColor(
    TransferPickedDocument document,
  ) {
    if (document.isPdf) {
      return CorviaColors.danger;
    }

    if (document.isImage) {
      return context.cAccentReadable;
    }

    if (document.isDicom) {
      return CorviaColors.success;
    }

    if (document.isSpreadsheet) {
      return CorviaColors.success;
    }

    return CorviaColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      child: Scaffold(
        backgroundColor: context.cBgPrimary,
        appBar: AppBar(
          backgroundColor: context.cBgSecondary,
          foregroundColor: context.cTextPrimary,
          title: const Text(
            'Upload Transfer Document',
          ),
          actions: [
            if (_uploading)
              const Padding(
                padding: EdgeInsets.only(right: 18),
                child: Center(
                  child: SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 780,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTransferSummary(),
                    const SizedBox(height: 18),
                    _buildFileSelectionPanel(),
                    const SizedBox(height: 18),
                    _buildDocumentDetailsPanel(),
                    if (_uploading || _uploadProgress > 0) ...[
                      const SizedBox(height: 18),
                      _buildUploadProgressPanel(),
                    ],
                    const SizedBox(height: 22),
                    _buildActions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransferSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: context.cAccentReadable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.transfer.transferNumber,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.transfer.patientName,
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _detailLine(
            'Source',
            widget.transfer.sourceHospitalName,
          ),
          _detailLine(
            'Destination',
            widget.transfer.destinationHospitalName,
          ),
          _detailLine(
            'Status',
            _humanize(widget.transfer.status),
          ),
        ],
      ),
    );
  }

  Widget _buildFileSelectionPanel() {
    final document = _selectedDocument;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Document',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'PDF, images, DICOM, Word, Excel and text files are supported. Maximum size: 25 MB.',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (document == null)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _picking || _uploading ? null : _pickDocument,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: context.cBgPrimary,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: context.cAccentReadable.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    if (_picking)
                      CircularProgressIndicator(
                        color: context.cAccentReadable,
                      )
                    else
                      Icon(
                        Icons.cloud_upload_rounded,
                        color: context.cAccentReadable,
                        size: 42,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _picking ? 'Opening file picker...' : 'Choose Document',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Click to browse files on this device',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cBgPrimary,
                borderRadius: BorderRadius.circular(18),
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
                      color: _documentColor(document).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      _documentIcon(document),
                      color: _documentColor(document),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${document.displaySize} • '
                          '${document.mimeType}',
                          style: TextStyle(
                            color: context.cTextSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Choose another file',
                    onPressed: _uploading ? null : _pickDocument,
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove selected file',
                    onPressed: _uploading
                        ? null
                        : () {
                            setState(() {
                              _selectedDocument = null;
                              _uploadProgress = 0;
                              _uploadStatus = '';
                            });
                          },
                    icon: const Icon(
                      Icons.close_rounded,
                    ),
                    color: CorviaColors.danger,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentDetailsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document Details',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _documentType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Document type',
              border: OutlineInputBorder(),
            ),
            items: _documentTypes.map(
              (type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(
                    _humanize(type),
                  ),
                );
              },
            ).toList(),
            onChanged: _uploading
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _documentType = value;
                    });
                  },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            enabled: !_uploading,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Add a short description of the document',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isClinical,
            onChanged: _uploading
                ? null
                : (value) {
                    setState(() {
                      _isClinical = value;
                    });
                  },
            title: const Text(
              'Clinical document',
            ),
            subtitle: const Text(
              'Contains patient treatment or clinical information',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sharedWithDestination,
            onChanged: _uploading
                ? null
                : (value) {
                    setState(() {
                      _sharedWithDestination = value;
                    });
                  },
            title: const Text(
              'Share with destination hospital',
            ),
            subtitle: const Text(
              'Authorised destination staff can access this document',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgressPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _uploadProgress >= 1
                    ? Icons.check_circle_rounded
                    : Icons.cloud_upload_rounded,
                color: _uploadProgress >= 1
                    ? CorviaColors.success
                    : context.cAccentReadable,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _uploadStatus,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${(_uploadProgress * 100).round()}%',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _uploadProgress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _uploading
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _selectedDocument == null || _uploading || _picking
                ? null
                : _uploadDocument,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.cloud_upload_rounded,
                  ),
            label: Text(
              _uploading ? 'Uploading...' : 'Upload Document',
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailLine(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 6,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
