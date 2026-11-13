import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/reception_service.dart';
import '../../theme/app_theme.dart';

import 'reception_walk_in_page.dart';

enum ReceptionPatientSearchMode {
  browse,
  walkIn,
}

class ReceptionPatientSearchPage extends StatefulWidget {
  const ReceptionPatientSearchPage({
    super.key,
    this.mode = ReceptionPatientSearchMode.browse,
  });

  final ReceptionPatientSearchMode mode;

  @override
  State<ReceptionPatientSearchPage> createState() =>
      _ReceptionPatientSearchPageState();
}

class _ReceptionPatientSearchPageState
    extends State<ReceptionPatientSearchPage> {
  final ReceptionService _service = ReceptionService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  List<ReceptionPatient> _patients = <ReceptionPatient>[];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _patients = <ReceptionPatient>[];
        _loading = false;
        _error = null;
      });
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(value),
    );
  }

  Future<void> _search(String value) async {
    final searchText = value.trim();

    if (searchText.length < 2) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final patients = await _service.searchPatients(searchText);

      if (!mounted || _searchController.text.trim() != searchText) {
        return;
      }

      setState(() {
        _patients = patients;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && _searchController.text.trim() == searchText) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectPatient(ReceptionPatient patient) async {
    if (widget.mode == ReceptionPatientSearchMode.walkIn) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReceptionWalkInPage(patient: patient),
        ),
      );

      if (changed == true && mounted) {
        Navigator.of(context).pop(true);
      }

      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                color: CorviaColors.accent,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                patient.fullName,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                patient.patientNumber,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();

                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ReceptionWalkInPage(patient: patient),
                      ),
                    );

                    if (changed == true && mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Create Walk-In Check-In'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Reception booking is the next feature after walk-in check-in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == ReceptionPatientSearchMode.walkIn
        ? 'Select Walk-In Patient'
        : 'Search Patient';

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: Text(title),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Name, surname, patient number, ID or phone',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _patients = <ReceptionPatient>[];
                                _error = null;
                              });
                            },
                          ),
              ),
            ),
          ),
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!
                .replaceFirst('Exception: ', '')
                .replaceAll('PostgrestException(message: ', ''),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
        ),
      );
    }

    if (_searchController.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.manage_search_rounded,
                size: 54,
                color: context.cTextSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Search for a patient',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter at least two characters to search safely within this hospital.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.cTextSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_patients.isEmpty) {
      return Center(
        child: Text(
          'No patients found.',
          style: TextStyle(
            color: context.cTextSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _patients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final patient = _patients[index];
        final dob = patient.dateOfBirth == null
            ? 'Date of birth unavailable'
            : DateFormat('d MMM yyyy').format(patient.dateOfBirth!);

        return Card(
          color: context.cBgSecondary,
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: CircleAvatar(
              backgroundColor: CorviaColors.accent.withValues(alpha: 0.14),
              child: Icon(
                Icons.person_rounded,
                color: CorviaColors.accent,
              ),
            ),
            title: Text(
              patient.fullName,
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${patient.patientNumber}\n$dob'
                '${patient.phoneNumber.isEmpty ? '' : '\n${patient.phoneNumber}'}',
                style: TextStyle(
                  color: context.cTextSecondary,
                  height: 1.35,
                ),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: CorviaColors.accent,
            ),
            onTap: () => _selectPatient(patient),
          ),
        );
      },
    );
  }
}
