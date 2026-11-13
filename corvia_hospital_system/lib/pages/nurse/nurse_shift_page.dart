import 'package:flutter/material.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nurse_ward_picker.dart';

class NurseShiftPage extends StatefulWidget {
  const NurseShiftPage({
    super.key,
    this.service,
    this.showAppBar = true,
  });

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseShiftPage> createState() {
    return _NurseShiftPageState();
  }
}

class _NurseShiftPageState extends State<NurseShiftPage> {
  late final NurseService _service = widget.service ?? NurseService();

  final TextEditingController
      _clockInNoteController =
      TextEditingController();

  final TextEditingController
      _handoverNoteController =
      TextEditingController();

  NurseContext? _context;

  Map<String, dynamic>? _activeShift;

  List<Map<String, dynamic>>
      _shiftHistory = [];

  bool _loading = true;
  bool _saving = false;

  String? _error;

  String? _selectedWardId;
  List<NurseWard> _wards = [];

  String _selectedShiftType =
      'Day Shift';

  static const List<String> _shiftTypes = [
    'Day Shift',
    'Night Shift',
    'Morning Shift',
    'Afternoon Shift',
    'Weekend Shift',
    'Overtime Shift',
  ];

  @override
  void initState() {
    super.initState();

    _loadPage();
  }

  @override
  void dispose() {
    _clockInNoteController.dispose();
    _handoverNoteController.dispose();

    super.dispose();
  }

  Future<void> _loadPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final workspace = await _service.loadWorkspace();
      final nurseContext = workspace.context;

      final results =
          await Future.wait<dynamic>([
        _service.loadActiveShift(
          nurseContext,
        ),
        _service.loadShiftHistory(
          nurseContext,
        ),
      ]);

      final activeShift =
          results[0] as Map<String, dynamic>?;

      final history =
          results[1]
              as List<Map<String, dynamic>>;

      if (!mounted) {
        return;
      }

      _context = nurseContext;
      _wards = workspace.wards;
      if (!_wards.any((ward) => ward.id == _selectedWardId)) {
        _selectedWardId = null;
      }
      _activeShift = activeShift;
      _shiftHistory = history;

      _handoverNoteController.text =
          activeShift?['handover_note']
                  ?.toString() ??
              '';

      if (activeShift != null) {
        final shiftType =
            activeShift['shift_type']
                ?.toString()
                .trim();

        if (shiftType != null &&
            _shiftTypes.contains(shiftType)) {
          _selectedShiftType =
              shiftType;
        }
      }

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _cleanError(
          error,
        );
      });
    }
  }

  Future<void> _refreshShiftData() async {
    final nurseContext =
        _context;

    if (nurseContext == null) {
      await _loadPage();
      return;
    }

    final results =
        await Future.wait<dynamic>([
      _service.loadActiveShift(
        nurseContext,
      ),
      _service.loadShiftHistory(
        nurseContext,
      ),
    ]);

    if (!mounted) {
      return;
    }

    setState(() {
      _activeShift =
          results[0] as Map<String, dynamic>?;

      _shiftHistory =
          results[1]
              as List<Map<String, dynamic>>;

      _handoverNoteController.text =
          _activeShift?['handover_note']
                  ?.toString() ??
              '';
    });
  }

  Future<void> _clockIn() async {
    if (_saving ||
        _activeShift != null) {
      return;
    }

    final nurseContext =
        _context;

    if (nurseContext == null) {
      _message(
        'Nurse context is unavailable.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.clockIn(
        context: nurseContext,
        wardId: _selectedWardId ?? '',
        shiftType:
            _selectedShiftType,
        note:
            _clockInNoteController.text,
      );

      _clockInNoteController.clear();

      await _refreshShiftData();

      _message(
        'Clocked in successfully.',
      );
    } catch (error) {
      _message(
        'Could not clock in. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _startBreak() async {
    final nurseContext =
        _context;
    final shift =
        _activeShift;

    if (_saving ||
        nurseContext == null ||
        shift == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.startBreak(
        context: nurseContext,
        shift: shift,
      );

      await _refreshShiftData();

      _message(
        'Break started.',
      );
    } catch (error) {
      _message(
        'Could not start break. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _endBreak() async {
    final nurseContext =
        _context;
    final shift =
        _activeShift;

    if (_saving ||
        nurseContext == null ||
        shift == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.endBreak(
        context: nurseContext,
        shift: shift,
      );

      await _refreshShiftData();

      _message(
        'Break ended.',
      );
    } catch (error) {
      _message(
        'Could not end break. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveHandover() async {
    final nurseContext =
        _context;
    final shift =
        _activeShift;

    if (_saving ||
        nurseContext == null ||
        shift == null) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.saveHandover(
        context: nurseContext,
        shift: shift,
        note:
            _handoverNoteController.text,
      );

      await _refreshShiftData();

      _message(
        'Handover note saved.',
      );
    } catch (error) {
      _message(
        'Could not save handover note. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _clockOut() async {
    final nurseContext =
        _context;
    final shift =
        _activeShift;

    if (_saving ||
        nurseContext == null ||
        shift == null) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Clock out?',
          ),
          content: const Text(
            'Are you sure you want to end '
            'your current nursing shift?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  true,
                );
              },
              child: const Text(
                'Clock Out',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.clockOut(
        context: nurseContext,
        shift: shift,
        handoverNote:
            _handoverNoteController.text,
      );

      _handoverNoteController.clear();

      await _refreshShiftData();

      _message(
        'Clocked out successfully.',
      );
    } catch (error) {
      _message(
        'Could not clock out. '
        '${_cleanError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _formatDateTime(
    dynamic value,
  ) {
    final date =
        DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Not set';
    }

    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _durationText(
    dynamic startValue,
    dynamic endValue,
  ) {
    final start =
        DateTime.tryParse(
      startValue?.toString() ?? '',
    )?.toLocal();

    if (start == null) {
      return '0 min';
    }

    final end =
        DateTime.tryParse(
              endValue?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now();

    final duration =
        end.difference(
      start,
    );

    if (duration.isNegative) {
      return '0 min';
    }

    final hours =
        duration.inHours;
    final minutes =
        duration.inMinutes.remainder(
      60,
    );

    if (hours == 0) {
      return '$minutes min';
    }

    return '${hours}h ${minutes}m';
  }

  String _prettyStatus(
    dynamic value,
  ) {
    final raw =
        value
            ?.toString()
            .trim()
            .replaceAll(
              '_',
              ' ',
            ) ??
        '';

    if (raw.isEmpty) {
      return 'Unknown';
    }

    return raw
        .split(
          RegExp(r'\s+'),
        )
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(
          ' ',
        );
  }

  String _cleanError(
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
          content: Text(
            message,
          ),
        ),
      );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text(
          'Nurse Shift',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _saving
                    ? null
                    : _loadPage,
            icon:
                const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ) : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child:
            CircularProgressIndicator(
          color:
              CorviaColors.accent,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child:
              ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 520,
            ),
            child:
                Column(
              children: [
                Icon(
                  Icons.error_outline,
                  color:
                      CorviaColors.danger,
                  size:
                      56,
                ),
                const SizedBox(
                  height: 15,
                ),
                Text(
                  'Could not load Nurse Shift',
                  style:
                      TextStyle(
                    color:
                        context.cTextPrimary,
                    fontSize:
                        20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                SelectableText(
                  _error!,
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    color:
                        context.cTextSecondary,
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
                FilledButton.icon(
                  onPressed:
                      _loadPage,
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
        ),
      );
    }

    return RefreshIndicator(
      onRefresh:
          _loadPage,
      child:
          ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.all(
          17,
        ),
        children: [
          _header(),
          const SizedBox(
            height: 15,
          ),
          if (_activeShift == null)
            _clockInCard()
          else
            _activeShiftCard(),
          const SizedBox(
            height: 15,
          ),
          _historyCard(),
          const SizedBox(
            height: 24,
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final nurse =
        _context!;

    return Container(
      padding:
          const EdgeInsets.all(
        19,
      ),
      decoration:
          BoxDecoration(
        gradient:
            LinearGradient(
          colors: [
            CorviaColors.accentDark,
            CorviaColors.accent,
          ],
        ),
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor:
                Colors.white,
            child: Icon(
              Icons.badge_outlined,
              color:
                  Color(0xFF0F766E),
              size: 31,
            ),
          ),
          const SizedBox(
            width: 14,
          ),
          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  nurse.nurseName,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontSize:
                        19,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  nurse.hospitalName,
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withValues(
                alpha: 0.16,
              ),
              borderRadius:
                  BorderRadius.circular(
                99,
              ),
            ),
            child:
                Text(
              _activeShift == null
                  ? 'OFFLINE'
                  : 'ON SHIFT',
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize:
                    10,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clockInCard() {
    return _NurseCard(
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon:
                Icons.login,
            title:
                'Clock In',
            subtitle:
                'Start a hospital-scoped nursing shift.',
          ),
          const SizedBox(
            height: 17,
          ),
          NurseWardPicker(
            wards: _wards,
            selectedWardId: _selectedWardId,
            onChanged: _saving ? null : (value) {
              setState(() => _selectedWardId = value);
            },
          ),
          const SizedBox(
            height: 13,
          ),
          DropdownButtonFormField<String>(
            initialValue:
                _selectedShiftType,
            decoration:
                const InputDecoration(
              labelText:
                  'Shift Type',
              border:
                  OutlineInputBorder(),
            ),
            items:
                _shiftTypes
                    .map(
                      (
                        value,
                      ) =>
                          DropdownMenuItem<String>(
                        value:
                            value,
                        child:
                            Text(
                          value,
                        ),
                      ),
                    )
                    .toList(),
            onChanged:
                _saving
                    ? null
                    : (
                        value,
                      ) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _selectedShiftType =
                              value;
                        });
                      },
          ),
          const SizedBox(
            height: 13,
          ),
          TextField(
            controller:
                _clockInNoteController,
            enabled:
                !_saving,
            minLines:
                2,
            maxLines:
                4,
            decoration:
                const InputDecoration(
              labelText:
                  'Clock-in Note',
              hintText:
                  'Example: Assigned to ICU beds 1 to 4.',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(
            height: 17,
          ),
          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed:
                  _saving || _selectedWardId == null || _wards.isEmpty
                      ? null
                      : _clockIn,
              icon:
                  _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2,
                          ),
                        )
                      : const Icon(
                          Icons.play_arrow,
                        ),
              label:
                  Text(
                _saving
                    ? 'Clocking In...'
                    : 'Clock In',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeShiftCard() {
    final shift =
        _activeShift!;

    final status =
        shift['status']
                ?.toString()
                .trim()
                .toLowerCase() ??
            'active';

    final onBreak =
        status == 'on_break';

    return _NurseCard(
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon:
                Icons.local_hospital_outlined,
            title:
                'Active Shift',
            subtitle:
                'Manage your current hospital shift.',
          ),
          const SizedBox(
            height: 17,
          ),
          Row(
            children: [
              Expanded(
                child:
                    _InfoBox(
                  label:
                      'Status',
                  value:
                      onBreak
                          ? 'On Break'
                          : 'Active',
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                    _InfoBox(
                  label:
                      'Duration',
                  value:
                      _durationText(
                    shift['clock_in_at'],
                    shift['clock_out_at'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              Expanded(
                child:
                    _InfoBox(
                  label:
                      'Ward',
                  value:
                      shift['ward']
                              ?.toString() ??
                          'Unknown',
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                    _InfoBox(
                  label:
                      'Break Time',
                  value:
                      '${shift['total_break_minutes'] ?? 0} min',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'Clocked in: '
            '${_formatDateTime(shift['clock_in_at'])}',
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
            ),
          ),
          const SizedBox(
            height: 13,
          ),
          TextField(
            controller:
                _handoverNoteController,
            enabled:
                !_saving,
            minLines:
                3,
            maxLines:
                6,
            decoration:
                const InputDecoration(
              labelText:
                  'Handover Notes',
              hintText:
                  'Patient updates and follow-up information.',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(
            height: 13,
          ),
          Row(
            children: [
              Expanded(
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _saving
                          ? null
                          : _saveHandover,
                  icon:
                      const Icon(
                    Icons.save_outlined,
                  ),
                  label:
                      const Text(
                    'Save Note',
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _saving
                          ? null
                          : onBreak
                              ? _endBreak
                              : _startBreak,
                  icon:
                      Icon(
                    onBreak
                        ? Icons.play_arrow
                        : Icons.pause,
                  ),
                  label:
                      Text(
                    onBreak
                        ? 'End Break'
                        : 'Start Break',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 11,
          ),
          SizedBox(
            width:
                double.infinity,
            child:
                FilledButton.icon(
              onPressed:
                  _saving
                      ? null
                      : _clockOut,
              icon:
                  const Icon(
                Icons.logout,
              ),
              label:
                  const Text(
                'Clock Out',
              ),
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    CorviaColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    return _NurseCard(
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon:
                Icons.history,
            title:
                'Recent Shifts',
            subtitle:
                'Your latest hospital shift records.',
          ),
          const SizedBox(
            height: 13,
          ),
          if (_shiftHistory.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 16,
              ),
              child:
                  Text(
                'No shift history yet.',
                style:
                    TextStyle(
                  color:
                      context.cTextSecondary,
                ),
              ),
            ),
          ..._shiftHistory.map(
            (
              shift,
            ) {
              final status =
                  shift['status']
                          ?.toString() ??
                      'unknown';

              return Container(
                margin:
                    const EdgeInsets.only(
                  bottom: 10,
                ),
                padding:
                    const EdgeInsets.all(
                  13,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      context.cBgPrimary,
                  borderRadius:
                      BorderRadius.circular(
                    14,
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
                    Icon(
                      status ==
                              'completed'
                          ? Icons.check_circle_outline
                          : Icons.schedule,
                      color:
                          status ==
                                  'completed'
                              ? CorviaColors.success
                              : CorviaColors.accent,
                    ),
                    const SizedBox(
                      width: 11,
                    ),
                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shift['ward'] ?? 'Unknown Ward'} • '
                            '${shift['shift_type'] ?? 'Shift'}',
                            style:
                                TextStyle(
                              color:
                                  context.cTextPrimary,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 4,
                          ),
                          Text(
                            'In: ${_formatDateTime(shift['clock_in_at'])}',
                            style:
                                TextStyle(
                              color:
                                  context.cTextSecondary,
                              fontSize:
                                  12,
                            ),
                          ),
                          Text(
                            'Out: ${_formatDateTime(shift['clock_out_at'])}',
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
                    ),
                    Text(
                      _prettyStatus(
                        status,
                      ),
                      style:
                          TextStyle(
                        color:
                            context.cTextMuted,
                        fontSize:
                            10,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NurseCard extends StatelessWidget {
  const _NurseCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        17,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgSecondary,
        borderRadius:
            BorderRadius.circular(
          21,
        ),
        border:
            Border.all(
          color:
              context.cDivider,
        ),
      ),
      child:
          child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor:
              CorviaColors.accent.withValues(
            alpha: 0.12,
          ),
          child:
              Icon(
            icon,
            color:
                CorviaColors.accent,
          ),
        ),
        const SizedBox(
          width: 11,
        ),
        Expanded(
          child:
              Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    TextStyle(
                  color:
                      context.cTextPrimary,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
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
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        11,
      ),
      decoration:
          BoxDecoration(
        color:
            context.cBgPrimary,
        borderRadius:
            BorderRadius.circular(
          13,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                TextStyle(
              color:
                  context.cTextSecondary,
              fontSize:
                  11,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            maxLines:
                2,
            overflow:
                TextOverflow.ellipsis,
            style:
                TextStyle(
              color:
                  context.cTextPrimary,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}