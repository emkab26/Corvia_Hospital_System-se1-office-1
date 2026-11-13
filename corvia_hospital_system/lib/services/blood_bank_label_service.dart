import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'blood_bank_service.dart';

/// Supplemental inventory reference. The original supplier label stays authoritative.
class BloodBankLabelService {
  static Future<Uint8List> build(BloodBankRow snapshot) async {
    String value(String key) => snapshot[key]?.toString() ?? 'Not recorded';
    String reference(String key) =>
        value(key).length <= 40 && !RegExp(r'[\r\n\t]').hasMatch(value(key))
            ? value(key)
            : 'See full reference in live record';
    String time(String key) {
      final d = DateTime.tryParse(value(key));
      if (d == null) {
        throw const FormatException('Label has an invalid timestamp');
      }
      return '${d.toUtc().add(const Duration(hours: 2)).toIso8601String().substring(0, 16).replaceAll('T', ' ')} SAST';
    }

    final qr = value('qr_value');
    if (qr != 'corvia:bb:unit:${value('id')}' ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(value('id'))) {
      throw const FormatException(
          'Label does not contain a valid unit reference');
    }
    if (value('unit_number').isEmpty ||
        value('unit_number').length > 100 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value('unit_number'))) {
      throw const FormatException(
          'The unit number cannot be printed safely. Check the live unit record.');
    }
    final expired = DateTime.parse(value('expires_at'))
            .isBefore(DateTime.parse(value('generated_at'))) ||
        DateTime.parse(value('expires_at'))
            .isAtSameMomentAs(DateTime.parse(value('generated_at')));
    final normal = pw.Font.ttf(await rootBundle.load('assets/fonts/Vera.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/VeraBd.ttf'));
    final document =
        pw.Document(theme: pw.ThemeData.withFont(base: normal, bold: bold));
    // Long source references are retrieved from the live record, not compressed
    // into an unreadable barcode label. Identifiers below are never truncated.
    document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(22),
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CORVIA · INVENTORY REFERENCE',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 15)),
                  pw.SizedBox(height: 8),
                  pw.Text(reference('hospital_name'),
                      style: const pw.TextStyle(fontSize: 11)),
                  pw.Divider(),
                  pw.Text(value('unit_number'),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: value('unit_number').length > 40 ? 10 : 16)),
                  pw.Text(reference('product_name'),
                      style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 10),
                  pw.Text('ABO / RhD: ${value('abo')} ${value('rhd')}',
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      'From recorded unit evidence; not a compatibility determination.',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 8),
                  pw.Text('Expiry: ${time('expires_at')}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text(
                      'Recorded status: ${value('status')}${expired ? ' · EXPIRED' : ''}'),
                  if (snapshot['recalled'] == true)
                    pw.Text('RECALLED - HOLD',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  if (snapshot['cold_chain_broken'] == true)
                    pw.Text('COLD-CHAIN BREAK - HOLD',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      'Location at preparation: ${reference('location_name')}'),
                  pw.Text('Source: ${value('source')}'),
                  if (snapshot['supplier'] != null)
                    pw.Text('Supplier: ${reference('supplier')}'),
                  if (snapshot['lot_number'] != null)
                    pw.Text('Lot: ${reference('lot_number')}'),
                  if (snapshot['donation_reference'] != null)
                    pw.Text('Donation: ${reference('donation_reference')}'),
                  if (snapshot['collected_at'] != null)
                    pw.Text('Collected: ${time('collected_at')}'),
                  pw.SizedBox(height: 12),
                  pw.Center(
                      child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qr,
                          width: 104,
                          height: 104,
                          drawText: false)),
                  pw.SizedBox(height: 6),
                  pw.Text('Unit ID: ${value('id')}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                      'Prepared: ${time('generated_at')} · Copy ${value('label_number')}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 10),
                  pw.Text(
                      'Scan to check current status in the authorised workspace. '
                      'Keep the original supplier label. This reference does not authorise transfusion.',
                      style: const pw.TextStyle(fontSize: 9)),
                ])));
    return document.save();
  }
}
