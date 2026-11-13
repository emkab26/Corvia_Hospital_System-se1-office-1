import "package:flutter/material.dart";
import "package:pretty_qr_code/pretty_qr_code.dart";

class GenerateCodePage extends StatefulWidget {
  const GenerateCodePage({super.key});

  @override
  State<GenerateCodePage> createState() => _GenerateCodePageState();
}

class _GenerateCodePageState extends State<GenerateCodePage> {
  final TextEditingController _controller = TextEditingController();
  String? qrData;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    setState(() => qrData = trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Generate QR Code"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _controller,
              onSubmitted: _onSubmitted,
              decoration: const InputDecoration(
                labelText: "Enter data for QR code",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (qrData != null) ...[
              PrettyQrView.data(data: qrData!),
            ] else
              const Text("Enter data to generate QR code"),
          ],
        ),
      ),
    );
  }
}
