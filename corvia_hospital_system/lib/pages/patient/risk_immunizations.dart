import 'package:flutter/material.dart';

// Added: Supabase import for DB persistence (review finding #6 — data was in-memory only).
import '../../services/supabase_service.dart';
// Added: Theme import to replace hardcoded Color(0xFF...) literals (theme sweep).
import '../../theme/app_theme.dart';

/// A dedicated form for tracking a patient's vaccination history and
/// known health risk factors.
///
/// When [patientId] is provided (doctor context), the page edits that
/// patient's data. Otherwise it resolves the signed-in patient's own ID.
/// Added patientId param so doctors can edit a specific patient's data
/// (review finding — page needed doctor-side navigation support).

class RisksImmunizations extends StatefulWidget {
  const RisksImmunizations({super.key, this.patientId});

  /// If null the page resolves the current patient automatically.
  final String? patientId;

  @override
  State<RisksImmunizations> createState() => _RisksImmunizationsState();
}

class _RisksImmunizationsState extends State<RisksImmunizations> {
  // Added: Loading/saving/error state flags so the UI can show a spinner
  // while fetching from Supabase and surface errors gracefully
  // (review finding #5 — no loading state infrastructure existed).
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  // Resolved IDs
  String? _patientId;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Added: Fetches existing immunization records and risk factors from
  // Supabase on page open so checkbox state reflects what's in the DB
  // (review finding #6 — previously reset to hardcoded defaults every visit).
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final client = SupabaseService.client;

      // Resolve patient & user IDs
      _patientId = widget.patientId ?? await SupabaseService.currentPatientId();
      _userId = SupabaseService.currentUserId;

      if (_patientId == null) {
        _errorMessage = 'Could not determine patient. Please try again.';
        return;
      }

      // Fetch immunization records + medical_details in parallel
      final Future<List<Map<String, dynamic>>> immunFuture = client
          .from('medical_records')
          .select('title')
          .eq('patient_id', _patientId!)
          .inFilter('record_type', ['immunization', 'vaccine']);

      final Future<Map<String, dynamic>?> detailsFuture = _userId != null
          ? client
              .from('medical_details')
              .select('medical_conditions')
              .eq('user_id', _userId!)
              .maybeSingle()
          : Future.value(null);

      final results = await Future.wait([immunFuture, detailsFuture]);

      // ── Merge immunizations ──
      final immunRows = results[0] as List? ?? [];
      final dbVaccines = <String>{};
      for (final row in immunRows) {
        final title = ((row as Map)['title'] ?? '').toString();
        if (title.isNotEmpty) dbVaccines.add(title);
      }
      // Mark defaults that exist in DB as checked; add any DB-only as custom.
      for (final key in vaccines.keys) {
        vaccines[key] = dbVaccines.contains(key);
      }
      for (final v in dbVaccines) {
        if (!vaccines.containsKey(v)) vaccines[v] = true;
      }

      // ── Merge risk factors ──
      final det = results[1] as Map<String, dynamic>?;
      if (det != null) {
        final conditions = det['medical_conditions'];
        final dbFactors = <String>{};
        if (conditions is List) {
          for (final c in conditions) {
            final s = c?.toString();
            if (s != null && s.isNotEmpty) dbFactors.add(s);
          }
        }
        for (final key in riskFactors.keys) {
          riskFactors[key] = dbFactors.contains(key);
        }
        for (final f in dbFactors) {
          if (!riskFactors.containsKey(f)) riskFactors[f] = true;
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to load data. Please try again.';
      debugPrint('RisksImmunizations._loadData error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Added: Persists the current checkbox state back to Supabase.
  // Vaccines → medical_records (record_type='immunization').
  // Risk factors → medical_details.medical_conditions.
  // (review finding #6 — no persistence existed).
  Future<void> _saveData() async {
    if (_patientId == null) return;
    setState(() => _isSaving = true);
    try {
      final client = SupabaseService.client;

      // 1) Vaccines → delete old immunization rows, insert checked ones.
      await client
          .from('medical_records')
          .delete()
          .eq('patient_id', _patientId!)
          .inFilter('record_type', ['immunization', 'vaccine']);

      final checkedVaccines = vaccines.entries
          .where((e) => e.value)
          .map((e) => {
                'patient_id': _patientId!,
                'record_type': 'immunization',
                'title': e.key,
                'description': 'Recorded via Risks & Immunizations form.',
                'record_date': DateTime.now().toIso8601String(),
              })
          .toList();

      if (checkedVaccines.isNotEmpty) {
        await client.from('medical_records').insert(checkedVaccines);
      }

      // 2) Risk factors → upsert medical_details.medical_conditions.
      if (_userId != null) {
        final checkedFactors = riskFactors.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();

        await client.from('medical_details').upsert(
          {
            'user_id': _userId!,
            'medical_conditions': checkedFactors,
          },
          onConflict: 'user_id',
        );
      }

      if (!mounted) return;
      _showSnack('Saved successfully.');
    } catch (e) {
      debugPrint('RisksImmunizations._saveData error: $e');
      if (!mounted) return;
      _showSnack('Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Vaccine checklist state
  Map<String, bool> vaccines = {
    'Influenza Vaccine': false,
    'COVID-19 Vaccine': false,
    'Hepatitis B Vaccine': false,
    'MMR (Measles, Mumps, Rubella)': false,
    'Tdap (Tetanus, Diphtheria, Pertussis)': false,
    'HPV Vaccine': false,
    'Pneumococcal Vaccine': false,
  };

  // Added: Full risk factors checklist state, mirroring the vaccines section.
  // Previously this was just a placeholder card with no interactivity
  // (review finding #2 — Risk Factors section was a placeholder).
  Map<String, bool> riskFactors = {
    'Diabetes': false,
    'Hypertension': false,
    'Heart Disease': false,
    'Asthma / COPD': false,
    'HIV / AIDS': false,
    'Tuberculosis (TB)': false,
    'Cancer': false,
    'Kidney Disease': false,
    'Liver Disease': false,
    'Obesity': false,
    'Smoking': false,
    'Alcohol Use': false,
  };

  // Controllers for adding custom entries.
  // _riskFactorController added for the new Risk Factors custom-add feature.
  final TextEditingController _vaccineController = TextEditingController();
  final TextEditingController _riskFactorController = TextEditingController();

  // Changed: Added early-return guards with SnackBar feedback for empty
  // and duplicate input — previously both cases were silent no-ops
  // (review finding #3 — no user feedback on failed add).
  void _addCustomVaccine() {
    final String newVaccine = _vaccineController.text.trim();
    if (newVaccine.isEmpty) {
      _showSnack('Please enter a vaccine name.');
      return;
    }
    if (vaccines.containsKey(newVaccine)) {
      _showSnack('"$newVaccine" is already in the list.');
      return;
    }
    setState(() {
      vaccines[newVaccine] = false;
      _vaccineController.clear();
    });
  }

  // Added: Mirrors _addCustomVaccine for the new Risk Factors section,
  // with the same SnackBar feedback pattern (review findings #2 and #3).
  void _addCustomRiskFactor() {
    final String newFactor = _riskFactorController.text.trim();
    if (newFactor.isEmpty) {
      _showSnack('Please enter a risk factor.');
      return;
    }
    if (riskFactors.containsKey(newFactor)) {
      _showSnack('"$newFactor" is already in the list.');
      return;
    }
    setState(() {
      riskFactors[newFactor] = false;
      _riskFactorController.clear();
    });
  }

  // Added: Shared helper to show SnackBars consistently across both
  // add methods and save feedback (review finding #3).
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _vaccineController.dispose();
    _riskFactorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Risks & Immunizations'),
      ),
      // Added: Save FAB to persist checkbox changes to Supabase.
      // Hidden during loading/error states. Shows a spinner while saving
      // (review finding #6 — no persistence).
      floatingActionButton: (_isLoading || _errorMessage != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveData,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save'),
              backgroundColor: CorviaColors.accent,
              foregroundColor: Colors.white,
            ),
      // Changed: Body now conditionally renders loading spinner, error
      // state with retry, or the main content — previously there was no
      // loading/error handling at all (review finding #5).
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: CorviaColors.danger, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.cTextSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Container(
        width: double.infinity,
        height: double.infinity,
        // Changed: Replaced hardcoded Color(0xFF0D1B2A)/Color(0xFF1B263B)
        // gradient with theme-aware context.cBgGradient (theme sweep).
        decoration: BoxDecoration(gradient: context.cBgGradient),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // === Immunizations Card ===
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading:
                          Icon(Icons.vaccines, color: CorviaColors.success, size: 32),
                      title: Text('Immunizations',
                          style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text('Select vaccines the patient has received',
                          style: TextStyle(color: context.cTextSecondary)),
                    ),
                    const Divider(),

                    // Changed: Added empty-state guard — shows placeholder
                    // text when the vaccines map is empty instead of a blank
                    // space (review finding #4 — no empty state for GridView).
                    if (vaccines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text('No vaccines added yet.',
                              style: TextStyle(
                                  color: context.cTextMuted, fontSize: 14)),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: vaccines.length,
                        itemBuilder: (context, index) {
                          String vaccineName = vaccines.keys.elementAt(index);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            activeColor: CorviaColors.success,
                            checkColor: Colors.white,
                            secondary: Icon(Icons.vaccines,
                                color: CorviaColors.success, size: 20),
                            title: Text(vaccineName,
                                style: TextStyle(
                                    color: context.cTextPrimary,
                                    fontSize: 14)),
                            value: vaccines[vaccineName],
                            onChanged: (bool? value) {
                              setState(() {
                                vaccines[vaccineName] = value ?? false;
                              });
                            },
                          );
                        },
                      ),

                    const Divider(),

                    // Add Custom Vaccine
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _vaccineController,
                            decoration: InputDecoration(
                              labelText: 'Add Custom Vaccine',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addCustomVaccine,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CorviaColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // === Risk Factors Card ===
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading:
                          Icon(Icons.warning, color: CorviaColors.danger, size: 32),
                      title: Text('Risk Factors',
                          style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text('Select known health risk factors',
                          style: TextStyle(color: context.cTextSecondary)),
                    ),
                    const Divider(),

                    // Added: Same empty-state guard for risk factors
                    // (review finding #4).
                    if (riskFactors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text('No risk factors added yet.',
                              style: TextStyle(
                                  color: context.cTextMuted, fontSize: 14)),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: riskFactors.length,
                        itemBuilder: (context, index) {
                          String factorName =
                              riskFactors.keys.elementAt(index);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            activeColor: CorviaColors.danger,
                            checkColor: Colors.white,
                            secondary: Icon(Icons.warning_amber,
                                color: CorviaColors.danger, size: 20),
                            title: Text(factorName,
                                style: TextStyle(
                                    color: context.cTextPrimary,
                                    fontSize: 14)),
                            value: riskFactors[factorName],
                            onChanged: (bool? value) {
                              setState(() {
                                riskFactors[factorName] = value ?? false;
                              });
                            },
                          );
                        },
                      ),

                    const Divider(),

                    // Add Custom Risk Factor
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _riskFactorController,
                            decoration: InputDecoration(
                              labelText: 'Add Custom Risk Factor',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addCustomRiskFactor,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CorviaColors.danger,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
