import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/settings_service.dart';
import 'lab_verifier_dashboard_page.dart';
import 'lab_worker_dashboard_page.dart';

/// Uses the live lab appointment, not the shared lab_worker profile role.
class LabWorkspacePage extends StatefulWidget {
  const LabWorkspacePage({super.key});
  @override
  State<LabWorkspacePage> createState() => _LabWorkspacePageState();
}

class _LabWorkspacePageState extends State<LabWorkspacePage> {
  late Future<bool> _verifier;
  @override
  void initState() {
    super.initState();
    _verifier = _resolve();
  }

  Future<bool> _resolve() async {
    final response =
        await Supabase.instance.client.rpc('corvia_current_lab_worker_context');
    if (response is! Map || response['can_verify_results'] is! bool) {
      throw const FormatException('Laboratory role could not be resolved.');
    }
    return response['can_verify_results'] as bool;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _verifier,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return snapshot.data!
                ? const LabVerifierDashboardPage()
                : const LabWorkerDashboardPage();
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Laboratory Workspace')),
            body: Center(
                child: snapshot.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              snapshot.error is PostgrestException
                                  ? (snapshot.error as PostgrestException)
                                      .message
                                  : snapshot.error.toString(),
                              textAlign: TextAlign.center),
                          TextButton(
                              onPressed: () =>
                                  setState(() => _verifier = _resolve()),
                              child: const Text('Retry')),
                          TextButton(
                              onPressed: () async {
                                try {
                                  await Supabase.instance.client.auth.signOut();
                                  SettingsService.instance.sessionUnlocked =
                                      false;
                                  if (context.mounted) {
                                    Navigator.of(context)
                                        .popUntil((route) => route.isFirst);
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Sign out failed: $error')));
                                  }
                                }
                              },
                              child: const Text('Sign out')),
                        ]))
                    : const CircularProgressIndicator()),
          );
        },
      );
}
