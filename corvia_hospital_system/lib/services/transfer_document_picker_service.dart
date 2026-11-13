import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class TransferDocumentPickerService {
  static const int maximumFileSizeBytes = 25 * 1024 * 1024;

  static const List<String> allowedExtensions = [
    'pdf',
    'dcm',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'txt',
    'doc',
    'docx',
    'xls',
    'xlsx',
  ];

  Future<TransferPickedDocument?> pickDocument() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: true,
      withReadStream: false,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final PlatformFile platformFile = result.files.single;

    final Uint8List? bytes = platformFile.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception(
        'The selected file could not be read. '
        'Select the document again.',
      );
    }

    if (platformFile.size > maximumFileSizeBytes) {
      throw Exception(
        'The selected file is larger than 25 MB.',
      );
    }

    final String extension = _extensionFromFile(
      platformFile,
    );

    if (!allowedExtensions.contains(extension)) {
      throw Exception(
        'This file type is not supported.',
      );
    }

    return TransferPickedDocument(
      fileName: platformFile.name,
      extension: extension,
      mimeType: mimeTypeForExtension(
        extension,
      ),
      bytes: bytes,
      sizeBytes: platformFile.size,
    );
  }

  String _extensionFromFile(
    PlatformFile file,
  ) {
    final String? suppliedExtension = file.extension?.trim().toLowerCase();

    if (suppliedExtension != null && suppliedExtension.isNotEmpty) {
      return suppliedExtension;
    }

    final String name = file.name.trim();

    if (!name.contains('.')) {
      return '';
    }

    return name.split('.').last.trim().toLowerCase();
  }

  static String mimeTypeForExtension(
    String extension,
  ) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';

      case 'dcm':
        return 'application/dicom';

      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';

      case 'png':
        return 'image/png';

      case 'webp':
        return 'image/webp';

      case 'heic':
        return 'image/heic';

      case 'heif':
        return 'image/heif';

      case 'txt':
        return 'text/plain';

      case 'doc':
        return 'application/msword';

      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.'
            'wordprocessingml.document';

      case 'xls':
        return 'application/vnd.ms-excel';

      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.sheet';

      default:
        return 'application/octet-stream';
    }
  }
}

class TransferPickedDocument {
  const TransferPickedDocument({
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.bytes,
    required this.sizeBytes,
  });

  final String fileName;
  final String extension;
  final String mimeType;

  final Uint8List bytes;
  final int sizeBytes;

  String get displaySize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }

    if (sizeBytes < 1024 * 1024) {
      final double kilobytes = sizeBytes / 1024;

      return '${kilobytes.toStringAsFixed(1)} KB';
    }

    final double megabytes = sizeBytes / (1024 * 1024);

    return '${megabytes.toStringAsFixed(1)} MB';
  }

  bool get isImage {
    return {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'heic',
      'heif',
    }.contains(extension);
  }

  bool get isPdf {
    return extension == 'pdf';
  }

  bool get isDicom {
    return extension == 'dcm';
  }

  bool get isWordDocument {
    return {
      'doc',
      'docx',
    }.contains(extension);
  }

  bool get isSpreadsheet {
    return {
      'xls',
      'xlsx',
    }.contains(extension);
  }
}
