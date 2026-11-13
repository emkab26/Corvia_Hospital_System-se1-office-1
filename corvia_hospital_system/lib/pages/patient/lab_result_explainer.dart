import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

class LabResultExplainerPage extends StatefulWidget {
  const LabResultExplainerPage({
    super.key,
    this.initialText,
    this.testName,
    this.labResultId,
  });

  final String? initialText;
  final String? testName;
  final String? labResultId;

  @override
  State<LabResultExplainerPage> createState() {
    return _LabResultExplainerPageState();
  }
}

class _LabResultExplainerPageState extends State<LabResultExplainerPage> {
  late final TextEditingController _controller;

  String _explanation = '';

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.initialText?.trim() ?? '');
  }

  Future<void> _explain() async {
    if (_isLoading) {
      return;
    }

    final text = _controller.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Enter or load a laboratory result first.'),
          ),
        );

      return;
    }

    setState(() {
      _isLoading = true;
      _explanation = '';
    });

    await Future<void>.delayed(const Duration(milliseconds: 700));

    if (!mounted) {
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('Important')),
            ],
          ),
          content: const Text(
            'This feature helps simplify laboratory terminology. '
            'It is not a diagnosis and does not replace advice '
            'from your doctor or healthcare professional.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (accepted != true) {
      setState(() {
        _isLoading = false;
      });

      return;
    }

    final testTitle = widget.testName?.trim().isNotEmpty == true
        ? widget.testName!.trim()
        : 'Laboratory Result';

    setState(() {
      _explanation =
          '''
$testTitle

Original result:
$text

In simple terms:
• Laboratory reports may contain medical terms, measurements and reference ranges that can be difficult to understand.
• A result outside a reference range does not automatically mean that you have a medical condition.
• Results must be interpreted together with your symptoms, medical history, medicines and other investigations.
• Your doctor or healthcare professional is the correct person to explain whether a result is clinically important for you.
• Do not change medication, treatment or dosage based only on this explanation.
• If you feel seriously unwell or your symptoms are worsening, seek appropriate medical care.
''';

      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = SettingsService.instance.themeVariant;

    final loadedFromResult = widget.initialText?.trim().isNotEmpty == true;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Lab Result Explainer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (loadedFromResult) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CorviaColors.accent.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.biotech_outlined,
                          color: CorviaColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.testName?.trim().isNotEmpty == true
                                ? 'Loaded from ${widget.testName}'
                                : 'Loaded from your laboratory result',
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: CorviaColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CorviaColors.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: CorviaColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'For the clearest context, open Lab Results and '
                            'choose “Explain Result” on a completed result. '
                            'You can also paste result text below.',
                            style: TextStyle(
                              color: context.cTextSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _controller,
                  minLines: 6,
                  maxLines: 12,
                  style: TextStyle(color: context.cTextPrimary),
                  decoration: InputDecoration(
                    labelText: loadedFromResult
                        ? 'Laboratory result'
                        : 'Paste laboratory result text here',
                    labelStyle: TextStyle(color: context.cTextSecondary),
                    filled: true,
                    fillColor: context.cBgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _explain,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isLoading
                          ? 'Preparing explanation...'
                          : 'Explain Lab Result',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxWidth < 360
                          ? constraints.maxWidth
                          : 320.0;

                      return Center(
                        child: Lottie.asset(
                          activeTheme.loaderAnimation,
                          width: size,
                          height: size,
                        ),
                      );
                    },
                  )
                else if (_explanation.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CorviaColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: CorviaColors.warning.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: CorviaColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'For information only. '
                            'This is not a diagnosis and must be '
                            'reviewed by a healthcare professional.',
                            style: TextStyle(color: context.cTextPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.cBgSecondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: CorviaColors.divider),
                    ),
                    child: SelectableText(
                      _explanation,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
