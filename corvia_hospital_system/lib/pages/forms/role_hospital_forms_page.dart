import 'package:flutter/material.dart';

import '../../services/hospital_form_context_service.dart';
import 'hospital_forms_page.dart';

class RoleHospitalFormsPage extends StatefulWidget {
  const RoleHospitalFormsPage({
    super.key,
    this.hospitalId,
    this.patientId,
    this.admissionId,
    this.contextType,
    this.contextId,
    this.title,
    this.patientVisibleOnly,
    this.allowCreate,
  });

  final String? hospitalId;
  final String? patientId;
  final String? admissionId;

  final String? contextType;
  final String? contextId;

  final String? title;

  final bool? patientVisibleOnly;
  final bool? allowCreate;

  @override
  State<RoleHospitalFormsPage> createState() {
    return _RoleHospitalFormsPageState();
  }
}

class _RoleHospitalFormsPageState extends State<RoleHospitalFormsPage> {
  final HospitalFormContextService _service = HospitalFormContextService();

  HospitalFormLaunchContext? _resolvedContext;

  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _resolveContext();
  }

  Future<void> _resolveContext() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final resolvedContext = await _service.resolve(
        hospitalId: widget.hospitalId,
        patientId: widget.patientId,
        admissionId: widget.admissionId,
        contextType: widget.contextType,
        contextId: widget.contextId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _resolvedContext = resolvedContext;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = _friendlyError(
          error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Hospital Forms',
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final errorMessage = _errorMessage;

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Hospital Forms',
          ),
        ),
        body: _ContextErrorState(
          message: errorMessage,
          onRetry: _resolveContext,
        ),
      );
    }

    final resolvedContext = _resolvedContext;

    if (resolvedContext == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Hospital Forms',
          ),
        ),
        body: const Center(
          child: Text(
            'Hospital form context is unavailable.',
          ),
        ),
      );
    }

    return HospitalFormsPage(
      hospitalId: resolvedContext.hospitalId,
      patientId: resolvedContext.patientId,
      admissionId: resolvedContext.admissionId,
      contextType: resolvedContext.contextType,
      contextId: resolvedContext.contextId,
      title: widget.title ?? resolvedContext.formsTitle,
      patientVisibleOnly:
          widget.patientVisibleOnly ?? resolvedContext.patientVisibleOnly,
      allowCreate: widget.allowCreate ?? resolvedContext.allowCreate,
    );
  }
}

class _ContextErrorState extends StatelessWidget {
  const _ContextErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Unable to open hospital forms',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _friendlyError(
  Object error,
) {
  if (error is HospitalFormContextException) {
    return error.message;
  }

  final message = error.toString().trim();

  if (message.startsWith(
    'Exception: ',
  )) {
    return message.substring(
      'Exception: '.length,
    );
  }

  if (message.isEmpty) {
    return 'An unknown form-context error occurred.';
  }

  return message;
}
