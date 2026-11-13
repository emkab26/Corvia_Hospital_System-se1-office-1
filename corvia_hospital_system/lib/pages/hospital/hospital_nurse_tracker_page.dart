import 'package:flutter/material.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';

class HospitalNurseTrackerPage
    extends StatefulWidget {
  const HospitalNurseTrackerPage({
    super.key,
  });

  @override
  State<HospitalNurseTrackerPage>
      createState() {
    return _HospitalNurseTrackerPageState();
  }
}

class _HospitalNurseTrackerPageState
    extends State<HospitalNurseTrackerPage> {
  final NurseService _service =
      NurseService();

  List<Map<String, dynamic>>
      _nurses = [];

  List<Map<String, dynamic>>
      _unlinked = [];

  bool _loading = true;
  bool _saving = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results =
          await Future.wait([
        _service.loadAdminHospitalNurses(),
        _service.loadAdminUnlinkedNurses(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _nurses =
            results[0];

        _unlinked =
            results[1];

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _clean(
          error,
        );
      });
    }
  }

  String _name(
    Map<String, dynamic> nurse,
  ) {
    final value =
        nurse['nurse_name']
            ?.toString()
            .trim();

    if (value != null &&
        value.isNotEmpty) {
      return value;
    }

    return nurse['email']
            ?.toString() ??
        'Nurse';
  }

  bool _active(
    Map<String, dynamic> nurse,
  ) {
    final value =
        nurse['is_active'];

    return value == true ||
        value
                ?.toString()
                .toLowerCase() ==
            'true';
  }

  String _shiftStatus(
    Map<String, dynamic> nurse,
  ) {
    final raw =
        nurse['shift_status']
            ?.toString()
            .trim();

    if (raw == null ||
        raw.isEmpty) {
      return 'Off Shift';
    }

    if (raw == 'on_break') {
      return 'On Break';
    }

    return 'On Shift';
  }

  Color _shiftColor(
    Map<String, dynamic> nurse,
  ) {
    final status =
        nurse['shift_status']
            ?.toString();

    if (status ==
        'on_break') {
      return CorviaColors.warning;
    }

    if (status ==
        'active') {
      return CorviaColors.success;
    }

    return context.cTextMuted;
  }

  Future<void> _linkNurse(
    Map<String, dynamic> nurse,
  ) async {
    if (_saving) {
      return;
    }

    final profileId =
        nurse['profile_id']
            ?.toString()
            .trim();

    if (profileId == null ||
        profileId.isEmpty) {
      _message(
        'The selected nurse has no profile ID.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.linkNurseToAdminHospital(
        profileId:
            profileId,
      );

      _message(
        '${_name(nurse)} linked to this hospital.',
      );

      await _load();
    } catch (error) {
      _message(
        'Could not link nurse. '
        '${_clean(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _showAddNurse() async {
    if (_unlinked.isEmpty) {
      _message(
        'No unlinked active nurse accounts are available.',
      );
      return;
    }

    await showDialog<void>(
      context:
          context,
      builder:
          (
            dialogContext,
          ) {
        return AlertDialog(
          title:
              const Text(
            'Link Nurse to Hospital',
          ),
          content:
              SizedBox(
            width:
                520,
            child:
                ListView.separated(
              shrinkWrap:
                  true,
              itemCount:
                  _unlinked.length,
              separatorBuilder:
                  (
                    _,
                    __,
                  ) =>
                      const Divider(),
              itemBuilder:
                  (
                    context,
                    index,
                  ) {
                final nurse =
                    _unlinked[index];

                return ListTile(
                  leading:
                      const CircleAvatar(
                    child:
                        Icon(
                      Icons.medical_services_outlined,
                    ),
                  ),
                  title:
                      Text(
                    _name(
                      nurse,
                    ),
                  ),
                  subtitle:
                      Text(
                    nurse['email']
                            ?.toString() ??
                        '',
                  ),
                  trailing:
                      FilledButton(
                    onPressed:
                        _saving
                            ? null
                            : () async {
                                Navigator.of(
                                  dialogContext,
                                ).pop();

                                await _linkNurse(
                                  nurse,
                                );
                              },
                    child:
                        const Text(
                      'Link',
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child:
                  const Text(
                'Close',
              ),
            ),
          ],
        );
      },
    );
  }

  String _clean(
    Object error,
  ) {
    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'PostgrestException(message: ',
          '',
        );
  }

  void _message(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final onShift =
        _nurses.where(
      (
        nurse,
      ) {
        final status =
            nurse['shift_status']
                ?.toString();

        return status ==
                'active' ||
            status ==
                'on_break';
      },
    ).length;

    final patientCount =
        _nurses.fold<int>(
      0,
      (
        total,
        nurse,
      ) =>
          total +
          (int.tryParse(
                nurse['assigned_patient_count']
                        ?.toString() ??
                    '',
              ) ??
              0),
    );

    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      appBar: AppBar(
        title:
            const Text(
          'Nurse Tracker',
        ),
        actions: [
          IconButton(
            tooltip:
                'Add Nurse',
            onPressed:
                _saving
                    ? null
                    : _showAddNurse,
            icon:
                const Icon(
              Icons.person_add_alt_1,
            ),
          ),
          IconButton(
            tooltip:
                'Refresh',
            onPressed:
                _loading
                    ? null
                    : _load,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : _error != null
                  ? _errorView()
                  : RefreshIndicator(
                      onRefresh:
                          _load,
                      child:
                          ListView(
                        physics:
                            const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.all(
                          18,
                        ),
                        children: [
                          _summary(
                            onShift,
                            patientCount,
                          ),
                          const SizedBox(
                            height: 18,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child:
                                    Text(
                                  'Hospital Nurses',
                                  style:
                                      TextStyle(
                                    color:
                                        context.cTextPrimary,
                                    fontSize:
                                        19,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed:
                                    _saving
                                        ? null
                                        : _showAddNurse,
                                icon:
                                    const Icon(
                                  Icons.person_add_alt_1,
                                ),
                                label:
                                    const Text(
                                  'Link Nurse',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          if (_nurses.isEmpty)
                            _empty()
                          else
                            ..._nurses.map(
                              _nurseCard,
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _summary(
    int onShift,
    int patientCount,
  ) {
    return LayoutBuilder(
      builder:
          (
            context,
            constraints,
          ) {
        final cards =
            [
          _SummaryData(
            label:
                'Linked Nurses',
            value:
                '${_nurses.length}',
            icon:
                Icons.medical_services_outlined,
          ),
          _SummaryData(
            label:
                'Currently On Shift',
            value:
                '$onShift',
            icon:
                Icons.schedule,
          ),
          _SummaryData(
            label:
                'Patient Assignments',
            value:
                '$patientCount',
            icon:
                Icons.people_alt_outlined,
          ),
          _SummaryData(
            label:
                'Unlinked Nurses',
            value:
                '${_unlinked.length}',
            icon:
                Icons.person_add_alt,
          ),
        ];

        return GridView.builder(
          shrinkWrap:
              true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              cards.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                constraints.maxWidth >=
                        800
                    ? 4
                    : 2,
            crossAxisSpacing:
                10,
            mainAxisSpacing:
                10,
            mainAxisExtent:
                130,
          ),
          itemBuilder:
              (
                context,
                index,
              ) {
            final item =
                cards[index];

            return Container(
              padding:
                  const EdgeInsets.all(
                15,
              ),
              decoration:
                  BoxDecoration(
                color:
                    context.cBgSecondary,
                borderRadius:
                    BorderRadius.circular(
                  17,
                ),
                border:
                    Border.all(
                  color:
                      context.cDivider,
                ),
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.icon,
                    color:
                        context.cAccentReadable,
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    style:
                        TextStyle(
                      color:
                          context.cTextPrimary,
                      fontSize:
                          25,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  Text(
                    item.label,
                    style:
                        TextStyle(
                      color:
                          context.cTextSecondary,
                      fontSize:
                          12,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _nurseCard(
    Map<String, dynamic> nurse,
  ) {
    final status =
        _shiftStatus(
      nurse,
    );

    final color =
        _shiftColor(
      nurse,
    );

    final count =
        int.tryParse(
              nurse['assigned_patient_count']
                      ?.toString() ??
                  '',
            ) ??
            0;

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 11,
      ),
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color:
              context.cDivider,
        ),
      ),
      child:
          Row(
        children: [
          CircleAvatar(
            backgroundColor:
                color.withValues(
              alpha:
                  0.12,
            ),
            child:
                Icon(
              Icons.medical_services_outlined,
              color:
                  color,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _name(
                    nurse,
                  ),
                  style:
                      TextStyle(
                    color:
                        context.cTextPrimary,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                if ((nurse['email']
                            ?.toString() ??
                        '')
                    .isNotEmpty)
                  Text(
                    nurse['email']
                        .toString(),
                    style:
                        TextStyle(
                      color:
                          context.cTextSecondary,
                      fontSize:
                          12,
                    ),
                  ),
                const SizedBox(
                  height: 5,
                ),
                Text(
                  status ==
                          'Off Shift'
                      ? '$status • $count assigned patient(s)'
                      : '$status • '
                          '${nurse['ward'] ?? 'Unknown Ward'} • '
                          '${nurse['shift_type'] ?? 'Shift'} • '
                          '$count patient(s)',
                  style:
                      TextStyle(
                    color:
                        color,
                    fontSize:
                        12,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _active(
              nurse,
            )
                ? Icons.check_circle
                : Icons.block,
            color:
                _active(
                  nurse,
                )
                    ? CorviaColors.success
                    : CorviaColors.danger,
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding:
          const EdgeInsets.all(
        30,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
      ),
      child:
          Column(
        children: [
          Icon(
            Icons.medical_services_outlined,
            size:
                50,
            color:
                context.cTextMuted,
          ),
          const SizedBox(
            height: 12,
          ),
          const Text(
            'No nurses linked to this hospital.',
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 13,
          ),
          FilledButton.icon(
            onPressed:
                _showAddNurse,
            icon:
                const Icon(
              Icons.person_add_alt_1,
            ),
            label:
                const Text(
              'Link Nurse',
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          24,
        ),
        child:
            Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size:
                  54,
              color:
                  CorviaColors.danger,
            ),
            const SizedBox(
              height: 12,
            ),
            SelectableText(
              _error!,
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 14,
            ),
            FilledButton.icon(
              onPressed:
                  _load,
              icon:
                  const Icon(
                Icons.refresh,
              ),
              label:
                  const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}