import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/visitor_request_service.dart';
import '../../theme/app_theme.dart';

class PatientVisitorAccessPage extends StatefulWidget {
  const PatientVisitorAccessPage({
    super.key,
  });

  @override
  State<PatientVisitorAccessPage> createState() =>
      _PatientVisitorAccessPageState();
}

class _PatientVisitorAccessPageState
    extends State<PatientVisitorAccessPage>
    with SingleTickerProviderStateMixin {
  final VisitorRequestService _service =
      VisitorRequestService();

  late final TabController _tabController;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _visitorPasses = [];
  List<Map<String, dynamic>> _myAccessPasses = [];
  List<Map<String, dynamic>> _restrictions = [];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 4,
      vsync: this,
    );

    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _safeLoad(
    Future<List<Map<String, dynamic>>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (error) {
      debugPrint(
        'Visitor Access partial load failed: $error',
      );

      return [];
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _safeLoad(
          _service.getMyVisitorRequests,
        ),
        _safeLoad(
          _service.getMyVisitorPasses,
        ),
        _safeLoad(
          _service.getMyVisitorAccessPasses,
        ),
        _safeLoad(
          _service.getMyVisitorRestrictions,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _requests = results[0];
        _visitorPasses = results[1];
        _myAccessPasses = results[2];
        _restrictions = results[3];

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _text(
    Map<String, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key];

      if (value == null) {
        continue;
      }

      final result = value.toString().trim();

      if (result.isNotEmpty &&
          result.toLowerCase() != 'null') {
        return result;
      }
    }

    return fallback;
  }

  DateTime? _date(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = map[key];

      if (raw == null) {
        continue;
      }

      final parsed = DateTime.tryParse(
        raw.toString(),
      );

      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    return null;
  }

  String _formatDate(
    DateTime? date,
  ) {
    if (date == null) {
      return 'Not specified';
    }

    return DateFormat(
      'dd MMM yyyy • HH:mm',
    ).format(date);
  }

  Color _statusColor(
    String status,
  ) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'active':
        return CorviaColors.success;

      case 'pending':
      case 'draft':
        return CorviaColors.warning;

      case 'denied':
      case 'revoked':
      case 'expired':
      case 'cancelled':
        return CorviaColors.danger;

      default:
        return context.cAccentReadable;
    }
  }

  Widget _statusBadge(
    String status,
  ) {
    final color = _statusColor(
      status,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Text(
        status.replaceAll(
          '_',
          ' ',
        ).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> _openInviteVisitor() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) {
          return VisitorInviteFormPage(
            service: _service,
          );
        },
      ),
    );

    if (created == true) {
      await _load();

      if (!mounted) {
        return;
      }

      _tabController.animateTo(
        0,
      );
    }
  }

  Future<void> _cancelRequest(
    Map<String, dynamic> request,
  ) async {
    final requestId =
        request['request_id']?.toString() ?? '';

    if (requestId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: context.cBgSecondary,
          title: Text(
            'Cancel Visitor Request?',
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'This visitor request will no longer be available for hospital approval.',
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Keep Request',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: Text(
                'Cancel Request',
                style: TextStyle(
                  color: CorviaColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.cancelMyVisitorRequest(
        requestId,
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not cancel request: $error',
            ),
          ),
        );
    }
  }

  Future<void> _copyToken(
    String token,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: token,
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Visitor QR token copied.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Visitor Access',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading
                ? null
                : _load,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(
              icon: Icon(
                Icons.pending_actions_rounded,
              ),
              text: 'Requests',
            ),
            Tab(
              icon: Icon(
                Icons.people_outline_rounded,
              ),
              text: 'Visitors',
            ),
            Tab(
              icon: Icon(
                Icons.qr_code_2_rounded,
              ),
              text: 'My Access',
            ),
            Tab(
              icon: Icon(
                Icons.policy_outlined,
              ),
              text: 'Restrictions',
            ),
          ],
        ),
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: _openInviteVisitor,
        icon: const Icon(
          Icons.person_add_alt_1_rounded,
        ),
        label: const Text(
          'Invite Visitor',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.cAccentReadable,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(
            24,
          ),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CorviaColors.danger,
            ),
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildRequests(),
        _buildVisitorPasses(),
        _buildMyAccess(),
        _buildRestrictions(),
      ],
    );
  }

  // ============================================================
  // REQUESTS I CREATED
  // ============================================================

  Widget _buildRequests() {
    if (_requests.isEmpty) {
      return _emptyState(
        icon: Icons.person_add_alt_1_outlined,
        title: 'No visitor requests',
        subtitle:
            'Invite a family member, friend or caregiver to visit you.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        itemCount: _requests.length,
        separatorBuilder: (_, __) {
          return const SizedBox(
            height: 12,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          final request = _requests[index];

          final name =
              '${_text(request, ['visitor_first_name'])} '
                      '${_text(request, ['visitor_surname'])}'
                  .trim();

          final status = _text(
            request,
            [
              'status',
            ],
            fallback: 'pending',
          );

          final relationship = _text(
            request,
            [
              'relationship_to_patient',
            ],
            fallback: 'Visitor',
          );

          final visit = _date(
            request,
            [
              'requested_visit_at',
            ],
          );

          final purpose = _text(
            request,
            [
              'visit_purpose',
            ],
            fallback: 'No visit purpose supplied',
          );

          final reviewReason = _text(
            request,
            [
              'review_reason',
            ],
          );

          return _card(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      color:
                          context.cAccentReadable,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty
                                ? 'Visitor'
                                : name,
                            style: TextStyle(
                              color:
                                  context.cTextPrimary,
                              fontWeight:
                                  FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            relationship.replaceAll(
                              '_',
                              ' ',
                            ),
                            style: TextStyle(
                              color: context
                                  .cTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusBadge(
                      status,
                    ),
                  ],
                ),
                const SizedBox(
                  height: 14,
                ),
                _infoRow(
                  Icons.calendar_month_outlined,
                  'Visit',
                  _formatDate(
                    visit,
                  ),
                ),
                _infoRow(
                  Icons.notes_outlined,
                  'Purpose',
                  purpose,
                ),
                if (reviewReason.isNotEmpty)
                  _infoRow(
                    Icons.info_outline,
                    'Hospital',
                    reviewReason,
                  ),
                if (status == 'pending') ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Align(
                    alignment:
                        Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _cancelRequest(
                          request,
                        );
                      },
                      icon: Icon(
                        Icons.cancel_outlined,
                        color:
                            CorviaColors.danger,
                      ),
                      label: Text(
                        'Cancel Request',
                        style: TextStyle(
                          color:
                              CorviaColors.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // PEOPLE WHO HAVE PASSES TO VISIT ME
  // ============================================================

  Widget _buildVisitorPasses() {
    if (_visitorPasses.isEmpty) {
      return _emptyState(
        icon: Icons.people_outline_rounded,
        title: 'No approved visitors',
        subtitle:
            'Visitor passes issued for people visiting you will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        itemCount: _visitorPasses.length,
        separatorBuilder: (_, __) {
          return const SizedBox(
            height: 12,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          final pass = _visitorPasses[index];

          final visitorName = _text(
            pass,
            [
              'visitor_name',
              'visitor_full_name',
            ],
            fallback: 'Visitor',
          );

          final status = _text(
            pass,
            [
              'status',
              'pass_status',
            ],
            fallback: 'pending',
          );

          return _card(
            child: Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  color:
                      _statusColor(status),
                  size: 32,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        visitorName,
                        style: TextStyle(
                          color:
                              context.cTextPrimary,
                          fontWeight:
                              FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        _text(
                          pass,
                          [
                            'pass_number',
                          ],
                          fallback:
                              'Visitor pass',
                        ),
                        style: TextStyle(
                          color: context
                              .cTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(
                  status,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // PASSES WHERE CURRENT ACCOUNT IS THE VISITOR
  // ============================================================

  Widget _buildMyAccess() {
    if (_myAccessPasses.isEmpty) {
      return _emptyState(
        icon: Icons.qr_code_2_rounded,
        title: 'No visitor access',
        subtitle:
            'When a hospital approves you as a visitor, your pass will appear here automatically.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        itemCount: _myAccessPasses.length,
        separatorBuilder: (_, __) {
          return const SizedBox(
            height: 16,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          return _myAccessCard(
            _myAccessPasses[index],
          );
        },
      ),
    );
  }

  Widget _myAccessCard(
    Map<String, dynamic> pass,
  ) {
    final hospitalName = _text(
      pass,
      [
        'hospital_name',
      ],
      fallback: 'Hospital',
    );

    final patientName = _text(
      pass,
      [
        'patient_name',
      ],
      fallback: 'Patient',
    );

    final passNumber = _text(
      pass,
      [
        'pass_number',
      ],
      fallback: 'Visitor Pass',
    );

    final token = _text(
      pass,
      [
        'qr_token',
      ],
    );

    final status = _text(
      pass,
      [
        'status',
      ],
      fallback: 'pending',
    );

    final relationship = _text(
      pass,
      [
        'relationship_to_patient',
      ],
      fallback: 'Visitor',
    );

    final validFrom = _date(
      pass,
      [
        'valid_from',
      ],
    );

    final validUntil = _date(
      pass,
      [
        'valid_until',
      ],
    );

    final isUsable = {
      'approved',
      'active',
    }.contains(
      status.toLowerCase(),
    );

    return Container(
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          24,
        ),
        border: Border.all(
          color: _statusColor(status)
              .withValues(
            alpha: 0.35,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 12,
            offset: const Offset(
              0,
              4,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              18,
            ),
            decoration: BoxDecoration(
              color: _statusColor(status)
                  .withValues(
                alpha: 0.07,
              ),
              borderRadius:
                  const BorderRadius.vertical(
                top: Radius.circular(
                  24,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _statusColor(status)
                        .withValues(
                      alpha: 0.13,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                  ),
                  child: Icon(
                    Icons.badge_rounded,
                    color:
                        _statusColor(status),
                    size: 27,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        hospitalName,
                        style: TextStyle(
                          color:
                              context.cTextPrimary,
                          fontWeight:
                              FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        'Visiting $patientName',
                        style: TextStyle(
                          color: context
                              .cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(
                  status,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(
              18,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    15,
                  ),
                  decoration: BoxDecoration(
                    color: context.cBgPrimary,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PASS NUMBER',
                        style: TextStyle(
                          color:
                              context.cTextMuted,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      SelectableText(
                        passNumber,
                        style: TextStyle(
                          color:
                              context.cTextPrimary,
                          fontSize: 21,
                          fontWeight:
                              FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                _infoRow(
                  Icons.people_outline,
                  'Relationship',
                  relationship.replaceAll(
                    '_',
                    ' ',
                  ),
                ),

                _infoRow(
                  Icons.login_rounded,
                  'Valid from',
                  _formatDate(
                    validFrom,
                  ),
                ),

                _infoRow(
                  Icons.logout_rounded,
                  'Valid until',
                  _formatDate(
                    validUntil,
                  ),
                ),

                if (isUsable &&
                    token.isNotEmpty) ...[
                  const SizedBox(
                    height: 18,
                  ),

                  Text(
                    'Visitor QR Pass',
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    'Show this QR code to reception or security when you arrive.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: context
                          .cTextSecondary,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Container(
                    padding:
                        const EdgeInsets.all(
                      14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(
                        18,
                      ),
                    ),
                    child: QrImageView(
                      data: token,
                      version:
                          QrVersions.auto,
                      size: 210,
                      backgroundColor:
                          Colors.white,
                    ),
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  SizedBox(
                    width: double.infinity,
                    child:
                        OutlinedButton.icon(
                      onPressed: () {
                        _copyToken(
                          token,
                        );
                      },
                      icon: const Icon(
                        Icons.copy_rounded,
                      ),
                      label: const Text(
                        'Copy Pass Token',
                      ),
                    ),
                  ),
                ],

                if (!isUsable) ...[
                  const SizedBox(
                    height: 14,
                  ),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color: _statusColor(status)
                          .withValues(
                        alpha: 0.08,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Text(
                      status == 'pending'
                          ? 'Hospital approval is still pending.'
                          : 'This visitor pass is not currently usable.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color:
                            _statusColor(status),
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESTRICTIONS
  // ============================================================

  Widget _buildRestrictions() {
    if (_restrictions.isEmpty) {
      return _emptyState(
        icon: Icons.verified_user_outlined,
        title: 'No visitor restrictions',
        subtitle:
            'There are currently no visitor restrictions on your patient record.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        itemCount: _restrictions.length,
        separatorBuilder: (_, __) {
          return const SizedBox(
            height: 12,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          final restriction =
              _restrictions[index];

          final type = _text(
            restriction,
            [
              'restriction_type',
            ],
            fallback:
                'Visitor restriction',
          );

          final reason = _text(
            restriction,
            [
              'reason',
            ],
            fallback:
                'No additional reason supplied.',
          );

          return _card(
            color: CorviaColors.warning
                .withValues(
              alpha: 0.06,
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.policy_outlined,
                  color:
                      CorviaColors.warning,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.replaceAll(
                          '_',
                          ' ',
                        ),
                        style: TextStyle(
                          color: context
                              .cTextPrimary,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        reason,
                        style: TextStyle(
                          color: context
                              .cTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card({
    required Widget child,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(
        16,
      ),
      decoration: BoxDecoration(
        color: color ?? context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
        boxShadow: [
          BoxShadow(
            color: context.cCardShadow,
            blurRadius: 8,
            offset: const Offset(
              0,
              3,
            ),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 17,
            color:
                context.cAccentReadable,
          ),
          const SizedBox(
            width: 8,
          ),
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: context
                    .cTextSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color:
                    context.cTextPrimary,
                fontSize: 12,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          24,
        ),
        children: [
          const SizedBox(
            height: 100,
          ),
          Icon(
            icon,
            size: 58,
            color:
                context.cAccentReadable,
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            title,
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  context.cTextPrimary,
              fontSize: 19,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            subtitle,
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color: context
                  .cTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INVITE VISITOR FORM
// =============================================================================

class VisitorInviteFormPage extends StatefulWidget {
  const VisitorInviteFormPage({
    super.key,
    required this.service,
  });

  final VisitorRequestService service;

  @override
  State<VisitorInviteFormPage> createState() =>
      _VisitorInviteFormPageState();
}

class _VisitorInviteFormPageState
    extends State<VisitorInviteFormPage> {
  final _formKey =
      GlobalKey<FormState>();

  final _firstNameController =
      TextEditingController();

  final _surnameController =
      TextEditingController();

  final _phoneController =
      TextEditingController();

  final _emailController =
      TextEditingController();

  final _purposeController =
      TextEditingController();

  String _relationship = 'family';

  late DateTime _visitDateTime;

  bool _submitting = false;

  static const Map<String, String>
      _relationships = {
    'spouse_partner':
        'Spouse / Partner',
    'parent': 'Parent',
    'child': 'Child',
    'sibling': 'Sibling',
    'guardian': 'Guardian',
    'next_of_kin': 'Next of Kin',
    'grandparent': 'Grandparent',
    'extended_family':
        'Extended Family',
    'caregiver': 'Caregiver',
    'family': 'Family',
    'friend': 'Friend',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();

    _visitDateTime =
        DateTime.now().add(
      const Duration(
        hours: 2,
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _purposeController.dispose();

    super.dispose();
  }

  Future<void> _chooseDate() async {
    final selected =
        await showDatePicker(
      context: context,
      initialDate:
          _visitDateTime,
      firstDate:
          DateTime.now(),
      lastDate:
          DateTime.now().add(
        const Duration(
          days: 90,
        ),
      ),
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    setState(() {
      _visitDateTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _visitDateTime.hour,
        _visitDateTime.minute,
      );
    });
  }

  Future<void> _chooseTime() async {
    final selected =
        await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(
        _visitDateTime,
      ),
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    setState(() {
      _visitDateTime = DateTime(
        _visitDateTime.year,
        _visitDateTime.month,
        _visitDateTime.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    FocusScope.of(context)
        .unfocus();

    if (!(_formKey.currentState
            ?.validate() ??
        false)) {
      return;
    }

    if (_visitDateTime.isBefore(
      DateTime.now(),
    )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Please choose a future visit time.',
            ),
          ),
        );

      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.service
          .createPatientVisitorRequest(
        firstName:
            _firstNameController.text,
        surname:
            _surnameController.text,
        relationship:
            _relationship,
        requestedVisitAt:
            _visitDateTime,
        phone:
            _phoneController.text,
        email:
            _emailController.text,
        visitPurpose:
            _purposeController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Visitor request submitted for hospital approval.',
            ),
          ),
        );

      Navigator.of(context).pop(
        true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not submit request: $error',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
      ),
      filled: true,
      fillColor:
          context.cBgSecondary,
      border: OutlineInputBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Invite Visitor',
        ),
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 700,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.all(
                        16,
                      ),
                      decoration:
                          BoxDecoration(
                        color: context
                            .cAccentReadable
                            .withValues(
                          alpha: 0.08,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Icon(
                            Icons
                                .info_outline_rounded,
                            color: context
                                .cAccentReadable,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child: Text(
                              'If the visitor already has a Corvia account, use the same email address they use to sign in. Their approved pass can then appear automatically in their account.',
                              style:
                                  TextStyle(
                                color: context
                                    .cTextSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    TextFormField(
                      controller:
                          _firstNameController,
                      decoration:
                          _decoration(
                        label:
                            'First Name',
                        icon: Icons
                            .person_outline,
                      ),
                      validator: (value) {
                        if (value ==
                                null ||
                            value
                                .trim()
                                .isEmpty) {
                          return 'Enter the visitor first name.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    TextFormField(
                      controller:
                          _surnameController,
                      decoration:
                          _decoration(
                        label: 'Surname',
                        icon: Icons
                            .person_outline,
                      ),
                      validator: (value) {
                        if (value ==
                                null ||
                            value
                                .trim()
                                .isEmpty) {
                          return 'Enter the visitor surname.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    TextFormField(
                      controller:
                          _phoneController,
                      keyboardType:
                          TextInputType
                              .phone,
                      decoration:
                          _decoration(
                        label:
                            'Phone Number',
                        icon: Icons
                            .phone_outlined,
                        hint: 'Optional',
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    TextFormField(
                      controller:
                          _emailController,
                      keyboardType:
                          TextInputType
                              .emailAddress,
                      decoration:
                          _decoration(
                        label:
                            'Visitor Corvia Email',
                        icon: Icons
                            .email_outlined,
                        hint:
                            'Recommended if they already use Corvia',
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    DropdownButtonFormField<
                        String>(
                      initialValue:
                          _relationship,
                      isExpanded: true,
                      decoration:
                          _decoration(
                        label:
                            'Relationship to Patient',
                        icon: Icons
                            .people_outline,
                      ),
                      items:
                          _relationships
                              .entries
                              .map(
                        (entry) {
                          return DropdownMenuItem<
                              String>(
                            value:
                                entry.key,
                            child: Text(
                              entry.value,
                            ),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value ==
                            null) {
                          return;
                        }

                        setState(() {
                          _relationship =
                              value;
                        });
                      },
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    TextFormField(
                      controller:
                          _purposeController,
                      minLines: 2,
                      maxLines: 4,
                      decoration:
                          _decoration(
                        label:
                            'Visit Purpose',
                        icon: Icons
                            .notes_rounded,
                        hint: 'Optional',
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    Text(
                      'Requested Visit',
                      style: TextStyle(
                        color: context
                            .cTextPrimary,
                        fontSize: 15,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                _chooseDate,
                            icon: const Icon(
                              Icons
                                  .calendar_month,
                            ),
                            label: Text(
                              DateFormat(
                                'dd MMM yyyy',
                              ).format(
                                _visitDateTime,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                              OutlinedButton
                                  .icon(
                            onPressed:
                                _chooseTime,
                            icon: const Icon(
                              Icons
                                  .schedule,
                            ),
                            label: Text(
                              DateFormat(
                                'HH:mm',
                              ).format(
                                _visitDateTime,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 26,
                    ),

                    FilledButton.icon(
                      onPressed:
                          _submitting
                              ? null
                              : _submit,
                      style:
                          FilledButton
                              .styleFrom(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 16,
                        ),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                                color:
                                    Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons
                                  .send_rounded,
                            ),
                      label: Text(
                        _submitting
                            ? 'Submitting...'
                            : 'Submit Visitor Request',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}