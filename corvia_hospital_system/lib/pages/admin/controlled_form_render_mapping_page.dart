import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/controlled_form_service.dart';
import '../../theme/app_theme.dart';

import 'controlled_form_visual_calibration_page.dart';

class ControlledFormRenderMappingPage extends StatefulWidget {
  const ControlledFormRenderMappingPage({
    super.key,
    required this.registry,
    required this.version,
  });

  final ControlledFormRegistryRecord registry;
  final ControlledFormVersionRecord version;

  @override
  State<ControlledFormRenderMappingPage> createState() =>
      _ControlledFormRenderMappingPageState();
}

class _ControlledFormRenderMappingPageState
    extends State<ControlledFormRenderMappingPage> {
  final ControlledFormService _service = ControlledFormService();

  bool _loading = true;
  bool _busy = false;

  String? _error;

  List<ControlledFormRenderProfile> _profiles = const [];
  List<ControlledFormRenderField> _fields = const [];

  ControlledFormRenderProfile? _selectedProfile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({
    String? preferredProfileId,
  }) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final profiles = await _service.loadRenderProfiles(
        controlledVersionId: widget.version.id,
      );

      ControlledFormRenderProfile? selected;

      if (preferredProfileId != null && preferredProfileId.trim().isNotEmpty) {
        for (final profile in profiles) {
          if (profile.id == preferredProfileId) {
            selected = profile;
            break;
          }
        }
      }

      if (selected == null && _selectedProfile != null) {
        for (final profile in profiles) {
          if (profile.id == _selectedProfile!.id) {
            selected = profile;
            break;
          }
        }
      }

      selected ??= _preferredProfile(
        profiles,
      );

      List<ControlledFormRenderField> fields = const [];

      if (selected != null) {
        fields = await _service.loadRenderFields(
          renderProfileId: selected.id,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = profiles;
        _selectedProfile = selected;
        _fields = fields;
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

  ControlledFormRenderProfile? _preferredProfile(
    List<ControlledFormRenderProfile> profiles,
  ) {
    if (profiles.isEmpty) {
      return null;
    }

    for (final profile in profiles) {
      if (profile.isDraft) {
        return profile;
      }
    }

    for (final profile in profiles) {
      if (profile.isUnderReview) {
        return profile;
      }
    }

    for (final profile in profiles) {
      if (profile.isApproved) {
        return profile;
      }
    }

    return profiles.first;
  }

  Future<void> _selectProfile(
    ControlledFormRenderProfile profile,
  ) async {
    if (_busy || _loading) {
      return;
    }

    setState(() {
      _selectedProfile = profile;
      _loading = true;
      _error = null;
    });

    try {
      final fields = await _service.loadRenderFields(
        renderProfileId: profile.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _fields = fields;
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

  Future<void> _createProfile() async {
    if (_busy) {
      return;
    }

    final result = await showDialog<_CreateRenderProfileResult>(
      context: context,
      builder: (_) {
        return const _CreateRenderProfileDialog();
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final profileId = await _service.createRenderProfile(
        controlledVersionId: widget.version.id,
        rendererType: result.rendererType,
        notes: result.notes,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'New PDF mapping revision created.',
      );

      await _load(
        preferredProfileId: profileId,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _addField() async {
    final profile = _selectedProfile;

    if (profile == null) {
      _showMessage(
        'Create a mapping revision first.',
        isError: true,
      );

      return;
    }

    if (!profile.canEdit) {
      _showMessage(
        'Only draft mapping revisions may be edited.',
        isError: true,
      );

      return;
    }

    final input = await showDialog<ControlledFormRenderFieldInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _RenderFieldDialog(
          renderProfileId: profile.id,
          registry: widget.registry,
          version: widget.version,
        );
      },
    );

    if (input == null || !mounted) {
      return;
    }

    await _saveField(
      input,
    );
  }

  Future<void> _editField(
    ControlledFormRenderField field,
  ) async {
    final profile = _selectedProfile;

    if (profile == null || !profile.canEdit) {
      _showMessage(
        'Only draft mapping revisions may be edited.',
        isError: true,
      );

      return;
    }

    final input = await showDialog<ControlledFormRenderFieldInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _RenderFieldDialog(
          renderProfileId: profile.id,
          registry: widget.registry,
          version: widget.version,
          existingField: field,
        );
      },
    );

    if (input == null || !mounted) {
      return;
    }

    await _saveField(
      input,
    );
  }

  Future<void> _saveField(
    ControlledFormRenderFieldInput input,
  ) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.saveRenderField(
        input: input,
      );

      final profileId = _selectedProfile?.id;

      if (!mounted) {
        return;
      }

      _showMessage(
        'PDF field mapping saved.',
      );

      await _load(
        preferredProfileId: profileId,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteField(
    ControlledFormRenderField field,
  ) async {
    final profile = _selectedProfile;

    if (profile == null || !profile.canEdit) {
      _showMessage(
        'Only draft mapping revisions may be edited.',
        isError: true,
      );

      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Delete Field Mapping?',
          ),
          content: Text(
            'Remove "${field.displayLabel}" from this '
            'mapping revision?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
              ),
              onPressed: () {
                Navigator.of(context).pop(
                  true,
                );
              },
              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.deleteRenderField(
        fieldId: field.id,
      );

      final profileId = profile.id;

      if (!mounted) {
        return;
      }

      _showMessage(
        'Field mapping deleted.',
      );

      await _load(
        preferredProfileId: profileId,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _submitForReview() async {
    final profile = _selectedProfile;

    if (profile == null || !profile.canSubmit) {
      return;
    }

    if (_fields.isEmpty) {
      _showMessage(
        'Add at least one verified PDF field mapping first.',
        isError: true,
      );

      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Submit Mapping for Review?',
          ),
          content: const Text(
            'After submission this revision moves into review. '
            'Check every page number and coordinate against the '
            'exact official PDF master before continuing.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  true,
                );
              },
              child: const Text(
                'Submit',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.submitRenderProfileForReview(
        renderProfileId: profile.id,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'PDF mapping submitted for review.',
      );

      await _load(
        preferredProfileId: profile.id,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _approveMapping() async {
    final profile = _selectedProfile;

    if (profile == null || !profile.canApprove) {
      return;
    }

    if (!widget.version.productionApproved) {
      _showMessage(
        'The official PDF master must first pass all controlled-form '
        'review gates and receive production approval.',
        isError: true,
      );

      return;
    }

    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Approve Exact PDF Mapping?',
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Approval makes this mapping revision immutable. '
                  'Any future coordinate change must be made in a '
                  'new mapping revision.',
                ),
                const SizedBox(
                  height: 16,
                ),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Approval notes',
                    hintText: 'Optional verification / review notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(
                  true,
                );
              },
              icon: const Icon(
                Icons.verified_outlined,
              ),
              label: const Text(
                'Approve Mapping',
              ),
            ),
          ],
        );
      },
    );

    final notes = notesController.text.trim();

    notesController.dispose();

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.approveRenderProfile(
        renderProfileId: profile.id,
        notes: notes.isEmpty ? null : notes,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Exact PDF mapping approved and locked.',
      );

      await _load(
        preferredProfileId: profile.id,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _retireMapping() async {
    final profile = _selectedProfile;

    if (profile == null || !profile.canRetire) {
      return;
    }

    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Retire Mapping Revision',
          ),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Retirement reason',
                hintText: 'Explain why this approved mapping is being retired.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: CorviaColors.danger,
              ),
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) {
                  return;
                }

                Navigator.of(context).pop(
                  value,
                );
              },
              child: const Text(
                'Retire',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (reason == null || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await _service.retireRenderProfile(
        renderProfileId: profile.id,
        reason: reason,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Mapping revision retired.',
      );

      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _inspectManifest() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final manifest = await _service.loadRenderManifest(
        controlledVersionId: widget.version.id,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text(
              'Approved Render Manifest',
            ),
            content: SizedBox(
              width: 620,
              child: manifest.mappingAvailable
                  ? SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dialogDetail(
                            'Mapping Revision',
                            '${manifest.mappingRevision ?? '-'}',
                          ),
                          _dialogDetail(
                            'Renderer',
                            manifest.rendererType ?? '-',
                          ),
                          _dialogDetail(
                            'Coordinate Origin',
                            manifest.coordinateOrigin ?? '-',
                          ),
                          _dialogDetail(
                            'Units',
                            manifest.pageUnit ?? '-',
                          ),
                          _dialogDetail(
                            'Mapped Fields',
                            manifest.fields.length.toString(),
                          ),
                          _dialogDetail(
                            'Source Master',
                            manifest.sourceDocumentName ?? '-',
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          const Text(
                            'The manifest contains internal rendering '
                            'coordinates and is intended for controlled '
                            'hospital staff/admin workflows.',
                          ),
                        ],
                      ),
                    )
                  : const Text(
                      'No approved render mapping is currently available '
                      'for this controlled master.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Close',
                ),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _cleanError(
          error,
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _dialogDetail(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
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
          backgroundColor: isError ? CorviaColors.danger : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _cleanError(
    Object error,
  ) {
    if (error is ControlledFormException) {
      return error.message;
    }

    return error
        .toString()
        .replaceFirst(
          'Exception: ',
          '',
        )
        .replaceFirst(
          'ControlledFormException: ',
          '',
        );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text(
          'Official PDF Mapping',
        ),
        actions: [
          IconButton(
            tooltip: 'Approved Manifest',
            onPressed: _busy ? null : _inspectManifest,
            icon: const Icon(
              Icons.schema_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _load,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedProfile?.canEdit == true
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addField,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Mapping',
              ),
            )
          : null,
      body: Stack(
        children: [
          _buildBody(),
          if (_busy)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.06,
                  ),
                  alignment: Alignment.topCenter,
                  child: const LinearProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _profiles.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null && _profiles.isEmpty) {
      return _buildErrorState();
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        if (constraints.maxWidth >= 1050) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 330,
                child: _buildProfileSidebar(),
              ),
              VerticalDivider(
                width: 1,
                color: context.cDivider,
              ),
              Expanded(
                child: _buildMainContent(),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildCompactProfileHeader(),
            Divider(
              height: 1,
              color: context.cDivider,
            ),
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.cBgSecondary,
              borderRadius: BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color: context.cDivider,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 54,
                  color: CorviaColors.danger,
                ),
                const SizedBox(
                  height: 14,
                ),
                Text(
                  'PDF mapping could not load',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  _error ?? 'Unknown error.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text(
                    'Try Again',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSidebar() {
    return Container(
      color: context.cBgSecondary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMasterCard(),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mapping Revisions',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Create Revision',
                onPressed: _busy ? null : _createProfile,
                icon: const Icon(
                  Icons.add_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          if (_profiles.isEmpty)
            _buildNoProfilesCard()
          else
            ..._profiles.map(
              _buildProfileTile,
            ),
        ],
      ),
    );
  }

  Widget _buildCompactProfileHeader() {
    return Container(
      width: double.infinity,
      color: context.cBgSecondary,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.registry.officialFormName,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            'Master v${widget.version.versionNumber} '
            '• ${widget.version.versionLabel}',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedProfile?.id,
                  decoration: const InputDecoration(
                    labelText: 'Mapping Revision',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _profiles.map(
                    (profile) {
                      return DropdownMenuItem<String>(
                        value: profile.id,
                        child: Text(
                          'Revision ${profile.mappingRevision} '
                          '• ${_prettyStatus(profile.status)}',
                        ),
                      );
                    },
                  ).toList(),
                  onChanged: _busy
                      ? null
                      : (profileId) {
                          if (profileId == null) {
                            return;
                          }

                          for (final profile in _profiles) {
                            if (profile.id == profileId) {
                              _selectProfile(
                                profile,
                              );

                              break;
                            }
                          }
                        },
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              IconButton.filledTonal(
                tooltip: 'New Mapping Revision',
                onPressed: _busy ? null : _createProfile,
                icon: const Icon(
                  Icons.add,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterCard() {
    final version = widget.version;

    final statusColor = version.productionApproved
        ? CorviaColors.success
        : CorviaColors.warning;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            color: context.cAccentReadable,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            widget.registry.officialFormName,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          if (widget.registry.formCode.isNotEmpty) ...[
            const SizedBox(
              height: 3,
            ),
            Text(
              widget.registry.formCode,
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(
            height: 12,
          ),
          _smallDetail(
            'Master',
            'v${version.versionNumber} • ${version.versionLabel}',
          ),
          if (version.officialFormNumber != null &&
              version.officialFormNumber!.trim().isNotEmpty)
            _smallDetail(
              'Official No.',
              version.officialFormNumber!,
            ),
          _smallDetail(
            'Review Gates',
            '${version.approvedGateCount}/7',
          ),
          const SizedBox(
            height: 8,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                20,
              ),
            ),
            child: Text(
              version.productionApproved
                  ? 'Production Approved'
                  : 'Not Production Approved',
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallDetail(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                color: context.cTextMuted,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProfilesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.layers_outlined,
            color: context.cTextMuted,
            size: 36,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            'No mapping revisions yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _createProfile,
            icon: const Icon(
              Icons.add,
            ),
            label: const Text(
              'Create Revision',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(
    ControlledFormRenderProfile profile,
  ) {
    final selected = _selectedProfile?.id == profile.id;

    final color = _profileStatusColor(
      profile.status,
    );

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Material(
        color: selected
            ? color.withValues(
                alpha: 0.08,
              )
            : context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          14,
        ),
        child: InkWell(
          onTap: _busy
              ? null
              : () {
                  _selectProfile(
                    profile,
                  );
                },
          borderRadius: BorderRadius.circular(
            14,
          ),
          child: Container(
            padding: const EdgeInsets.all(
              12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                14,
              ),
              border: Border.all(
                color: selected
                    ? color.withValues(
                        alpha: 0.65,
                      )
                    : context.cDivider,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: Text(
                    '${profile.mappingRevision}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revision ${profile.mappingRevision}',
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        '${_prettyStatus(profile.status)} '
                        '• ${_prettyStatus(profile.rendererType)}',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: color,
                    size: 19,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final profile = _selectedProfile;

    if (profile == null) {
      return _buildNoSelectedProfile();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _load(
          preferredProfileId: profile.id,
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          100,
        ),
        children: [
          _buildMappingHeader(
            profile,
          ),
          const SizedBox(
            height: 16,
          ),
          _buildCoordinateInfo(),
          const SizedBox(
            height: 18,
          ),
          _buildFieldsHeader(
            profile,
          ),
          const SizedBox(
            height: 10,
          ),
          if (_fields.isEmpty)
            _buildNoFieldsCard(
              profile,
            )
          else
            ..._fields.map(
              (field) => _buildFieldCard(
                profile,
                field,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoSelectedProfile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.design_services_outlined,
              size: 58,
              color: context.cTextMuted,
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              'Create the first PDF mapping revision',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Coordinates must be measured against the exact '
              'official PDF master. Corvia does not guess '
              'statutory form positions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.cTextSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _createProfile,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Create Mapping Revision',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingHeader(
    ControlledFormRenderProfile profile,
  ) {
    final color = _profileStatusColor(
      profile.status,
    );

    return Container(
      padding: const EdgeInsets.all(
        18,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          19,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                ),
                child: Icon(
                  profile.isApproved
                      ? Icons.verified_outlined
                      : Icons.design_services_outlined,
                  color: color,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mapping Revision ${profile.mappingRevision}',
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      '${_prettyStatus(profile.rendererType)} '
                      '• ${profile.coordinateOrigin} '
                      '• ${profile.pageUnit}',
                      style: TextStyle(
                        color: context.cTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    20,
                  ),
                ),
                child: Text(
                  _prettyStatus(
                    profile.status,
                  ),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (profile.notes != null && profile.notes!.trim().isNotEmpty) ...[
            const SizedBox(
              height: 14,
            ),
            Text(
              profile.notes!,
              style: TextStyle(
                color: context.cTextSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(
            height: 16,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (profile.canEdit)
                FilledButton.icon(
                  onPressed: _busy ? null : _addField,
                  icon: const Icon(
                    Icons.add,
                  ),
                  label: const Text(
                    'Add Field',
                  ),
                ),
              if (profile.canSubmit)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _submitForReview,
                  icon: const Icon(
                    Icons.rate_review_outlined,
                  ),
                  label: const Text(
                    'Submit for Review',
                  ),
                ),
              if (profile.canApprove)
                FilledButton.icon(
                  onPressed: _busy ? null : _approveMapping,
                  icon: const Icon(
                    Icons.verified_outlined,
                  ),
                  label: const Text(
                    'Approve Mapping',
                  ),
                ),
              if (profile.canRetire)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _retireMapping,
                  icon: const Icon(
                    Icons.archive_outlined,
                  ),
                  label: const Text(
                    'Retire Mapping',
                  ),
                ),
            ],
          ),
          if (profile.isApproved) ...[
            const SizedBox(
              height: 14,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                12,
              ),
              decoration: BoxDecoration(
                color: CorviaColors.success.withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: CorviaColors.success.withValues(
                    alpha: 0.22,
                  ),
                ),
              ),
              child: const Text(
                'This mapping is approved and immutable. '
                'Create a new revision for any future coordinate changes.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordinateInfo() {
    return Container(
      padding: const EdgeInsets.all(
        15,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(
          alpha: 0.07,
        ),
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: Colors.blue.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.blue,
          ),
          const SizedBox(
            width: 11,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visual PDF Calibration',
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  'When adding or editing a field, use '
                  '"Pick Position on PDF" to click directly on the '
                  'exact official master. Corvia converts that click '
                  'into PDF page, X and Y coordinates automatically.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsHeader(
    ControlledFormRenderProfile profile,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Field Mappings',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                '${_fields.length} mapped field'
                '${_fields.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: context.cTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (profile.canEdit)
          OutlinedButton.icon(
            onPressed: _busy ? null : _addField,
            icon: const Icon(
              Icons.add,
            ),
            label: const Text(
              'Add Mapping',
            ),
          ),
      ],
    );
  }

  Widget _buildNoFieldsCard(
    ControlledFormRenderProfile profile,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        28,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.grid_on_outlined,
            size: 48,
            color: context.cTextMuted,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            'No PDF fields mapped yet',
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            profile.canEdit
                ? 'Add the first verified field coordinate for this '
                    'official PDF master.'
                : 'This revision does not contain field mappings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextSecondary,
            ),
          ),
          if (profile.canEdit) ...[
            const SizedBox(
              height: 16,
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _addField,
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add First Mapping',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldCard(
    ControlledFormRenderProfile profile,
    ControlledFormRenderField field,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(
        15,
      ),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.cAccentReadable.withValues(
                    alpha: 0.09,
                  ),
                  borderRadius: BorderRadius.circular(
                    11,
                  ),
                ),
                child: Text(
                  '${field.pageNumber}',
                  style: TextStyle(
                    color: context.cAccentReadable,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.displayLabel,
                      style: TextStyle(
                        color: context.cTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    SelectableText(
                      field.mappingKey,
                      style: TextStyle(
                        color: context.cTextMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (field.requiredForRender)
                Container(
                  margin: const EdgeInsets.only(
                    right: 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: CorviaColors.warning.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    'Required',
                    style: TextStyle(
                      color: CorviaColors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (profile.canEdit)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editField(
                        field,
                      );
                    }

                    if (value == 'delete') {
                      _deleteField(
                        field,
                      );
                    }
                  },
                  itemBuilder: (_) {
                    return const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.edit_outlined,
                          ),
                          title: Text(
                            'Edit',
                          ),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_outline,
                          ),
                          title: Text(
                            'Delete',
                          ),
                        ),
                      ),
                    ];
                  },
                ),
            ],
          ),
          const SizedBox(
            height: 13,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fieldChip(
                Icons.layers_outlined,
                'Page ${field.pageNumber}',
              ),
              _fieldChip(
                Icons.source_outlined,
                '${_prettyStatus(field.sourceScope)}: '
                '${field.sourceDisplay}',
              ),
              _fieldChip(
                Icons.widgets_outlined,
                _prettyStatus(
                  field.widgetType,
                ),
              ),
              _fieldChip(
                Icons.open_with_outlined,
                'X ${_number(field.xPoints)} '
                '• Y ${_number(field.yPoints)}',
              ),
              if (field.widthPoints != null)
                _fieldChip(
                  Icons.width_normal_outlined,
                  'W ${_number(field.widthPoints!)}',
                ),
              if (field.heightPoints != null)
                _fieldChip(
                  Icons.height,
                  'H ${_number(field.heightPoints!)}',
                ),
              _fieldChip(
                Icons.format_size,
                '${_number(field.fontSizePoints)} pt',
              ),
              if (field.allowWrap)
                _fieldChip(
                  Icons.wrap_text,
                  'Wrap',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldChip(
    IconData icon,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color: context.cDivider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: context.cTextMuted,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            label,
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _profileStatusColor(
    String status,
  ) {
    switch (status.trim().toLowerCase()) {
      case 'approved':
        return CorviaColors.success;

      case 'review':
        return Colors.blue;

      case 'retired':
        return Colors.grey;

      case 'draft':
      default:
        return CorviaColors.warning;
    }
  }

  String _prettyStatus(
    String value,
  ) {
    final clean = value
        .trim()
        .replaceAll(
          '_',
          ' ',
        )
        .replaceAll(
          '-',
          ' ',
        );

    if (clean.isEmpty) {
      return 'Unknown';
    }

    return clean
        .split(
          RegExp(r'\s+'),
        )
        .where(
          (word) => word.isNotEmpty,
        )
        .map(
      (word) {
        if (word.length == 1) {
          return word.toUpperCase();
        }

        return '${word[0].toUpperCase()}'
            '${word.substring(1).toLowerCase()}';
      },
    ).join(' ');
  }

  String _number(
    double value,
  ) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }
}

// ============================================================================
// CREATE PROFILE DIALOG
// ============================================================================

class _CreateRenderProfileResult {
  const _CreateRenderProfileResult({
    required this.rendererType,
    this.notes,
  });

  final String rendererType;
  final String? notes;
}

class _CreateRenderProfileDialog extends StatefulWidget {
  const _CreateRenderProfileDialog();

  @override
  State<_CreateRenderProfileDialog> createState() =>
      _CreateRenderProfileDialogState();
}

class _CreateRenderProfileDialogState
    extends State<_CreateRenderProfileDialog> {
  final TextEditingController _notesController = TextEditingController();

  String _rendererType = 'pdf_overlay';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _CreateRenderProfileResult(
        rendererType: _rendererType,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      title: const Text(
        'New PDF Mapping Revision',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _rendererType,
              decoration: const InputDecoration(
                labelText: 'Renderer Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: 'pdf_overlay',
                  child: Text(
                    'PDF Overlay',
                  ),
                ),
                DropdownMenuItem<String>(
                  value: 'acroform',
                  child: Text(
                    'AcroForm Fields',
                  ),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _rendererType = value;
                });
              },
            ),
            const SizedBox(
              height: 14,
            ),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional notes about this mapping revision',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _rendererType == 'pdf_overlay'
                  ? 'PDF Overlay places text and marks at exact '
                      'X/Y coordinates on the approved PDF master.'
                  : 'AcroForm uses named fields already embedded '
                      'inside the approved PDF master.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.add,
          ),
          label: const Text(
            'Create Revision',
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FIELD MAPPING DIALOG
// ============================================================================

class _RenderFieldDialog extends StatefulWidget {
  const _RenderFieldDialog({
    required this.renderProfileId,
    required this.registry,
    required this.version,
    this.existingField,
  });

  final String renderProfileId;

  final ControlledFormRegistryRecord registry;
  final ControlledFormVersionRecord version;

  final ControlledFormRenderField? existingField;

  @override
  State<_RenderFieldDialog> createState() => _RenderFieldDialogState();
}

class _RenderFieldDialogState extends State<_RenderFieldDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _mappingKeyController;
  late final TextEditingController _labelController;
  late final TextEditingController _pageController;
  late final TextEditingController _sourceKeyController;
  late final TextEditingController _staticValueController;

  late final TextEditingController _xController;
  late final TextEditingController _yController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  late final TextEditingController _fontSizeController;
  late final TextEditingController _maxLinesController;

  late final TextEditingController _checkboxTrueController;
  late final TextEditingController _checkboxMarkController;

  late final TextEditingController _prefixController;
  late final TextEditingController _suffixController;
  late final TextEditingController _dateFormatController;

  late final TextEditingController _metadataController;

  String _sourceScope = 'form_value';
  String _widgetType = 'text';
  String _fontName = 'Helvetica';
  String _textAlign = 'left';

  bool _allowWrap = false;
  bool _requiredForRender = false;
  bool _openingCalibration = false;

  bool get _editing => widget.existingField != null;

  @override
  void initState() {
    super.initState();

    final field = widget.existingField;

    _mappingKeyController = TextEditingController(
      text: field?.mappingKey ?? '',
    );

    _labelController = TextEditingController(
      text: field?.label ?? '',
    );

    _pageController = TextEditingController(
      text: '${field?.pageNumber ?? 1}',
    );

    _sourceKeyController = TextEditingController(
      text: field?.sourceKey ?? '',
    );

    _staticValueController = TextEditingController(
      text: field?.staticValue ?? '',
    );

    _xController = TextEditingController(
      text: field == null
          ? ''
          : _formatNumber(
              field.xPoints,
            ),
    );

    _yController = TextEditingController(
      text: field == null
          ? ''
          : _formatNumber(
              field.yPoints,
            ),
    );

    _widthController = TextEditingController(
      text: field?.widthPoints == null
          ? ''
          : _formatNumber(
              field!.widthPoints!,
            ),
    );

    _heightController = TextEditingController(
      text: field?.heightPoints == null
          ? ''
          : _formatNumber(
              field!.heightPoints!,
            ),
    );

    _fontSizeController = TextEditingController(
      text: _formatNumber(
        field?.fontSizePoints ?? 9,
      ),
    );

    _maxLinesController = TextEditingController(
      text: '${field?.maxLines ?? 1}',
    );

    _checkboxTrueController = TextEditingController(
      text: field?.checkboxTrueValue ?? 'true',
    );

    _checkboxMarkController = TextEditingController(
      text: field?.checkboxMark ?? 'X',
    );

    _prefixController = TextEditingController(
      text: field?.prefixText ?? '',
    );

    _suffixController = TextEditingController(
      text: field?.suffixText ?? '',
    );

    _dateFormatController = TextEditingController(
      text: field?.dateFormat ?? 'dd/MM/yyyy',
    );

    _metadataController = TextEditingController(
      text: const JsonEncoder.withIndent(
        '  ',
      ).convert(
        field?.metadata ?? <String, dynamic>{},
      ),
    );

    _sourceScope = field?.sourceScope ?? 'form_value';
    _widgetType = field?.widgetType ?? 'text';
    _fontName = field?.fontName ?? 'Helvetica';
    _textAlign = field?.textAlign ?? 'left';

    _allowWrap = field?.allowWrap ?? false;
    _requiredForRender = field?.requiredForRender ?? false;
  }

  @override
  void dispose() {
    _mappingKeyController.dispose();
    _labelController.dispose();
    _pageController.dispose();
    _sourceKeyController.dispose();
    _staticValueController.dispose();

    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();

    _fontSizeController.dispose();
    _maxLinesController.dispose();

    _checkboxTrueController.dispose();
    _checkboxMarkController.dispose();

    _prefixController.dispose();
    _suffixController.dispose();
    _dateFormatController.dispose();

    _metadataController.dispose();

    super.dispose();
  }

  double? _controllerDouble(
    TextEditingController controller,
  ) {
    return double.tryParse(
      controller.text.trim(),
    );
  }

  int? _controllerInt(
    TextEditingController controller,
  ) {
    return int.tryParse(
      controller.text.trim(),
    );
  }

  Future<void> _pickVisualCoordinate() async {
    if (_openingCalibration) {
      return;
    }

    if (!widget.version.hasUploadedSource) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'The official PDF master must be uploaded first.',
            ),
          ),
        );

      return;
    }

    setState(() {
      _openingCalibration = true;
    });

    try {
      final result = await Navigator.of(context)
          .push<ControlledFormPdfCoordinateSelection>(
        MaterialPageRoute(
          builder: (_) {
            return ControlledFormVisualCalibrationPage(
              registry: widget.registry,
              version: widget.version,
              initialPageNumber: _controllerInt(
                    _pageController,
                  ) ??
                  1,
              initialXPoints: _controllerDouble(
                _xController,
              ),
              initialYPoints: _controllerDouble(
                _yController,
              ),
              initialWidthPoints: _controllerDouble(
                _widthController,
              ),
              initialHeightPoints: _controllerDouble(
                _heightController,
              ),
            );
          },
        ),
      );

      if (result == null || !mounted) {
        return;
      }

      setState(() {
        _pageController.text = result.pageNumber.toString();

        _xController.text = _formatNumber(
          result.xPoints,
        );

        _yController.text = _formatNumber(
          result.yPoints,
        );

        if (result.widthPoints != null) {
          _widthController.text = _formatNumber(
            result.widthPoints!,
          );
        }

        if (result.heightPoints != null) {
          _heightController.text = _formatNumber(
            result.heightPoints!,
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _openingCalibration = false;
        });
      }
    }
  }

  String _formatNumber(
    double value,
  ) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(
      2,
    );
  }

  String? _requiredText(
    String? value,
  ) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? _positiveInteger(
    String? value,
  ) {
    final parsed = int.tryParse(
      value?.trim() ?? '',
    );

    if (parsed == null || parsed < 1) {
      return 'Enter a number of 1 or more';
    }

    return null;
  }

  String? _coordinate(
    String? value,
  ) {
    final parsed = double.tryParse(
      value?.trim() ?? '',
    );

    if (parsed == null || parsed < 0) {
      return 'Enter a valid coordinate';
    }

    return null;
  }

  String? _optionalPositiveNumber(
    String? value,
  ) {
    final clean = value?.trim() ?? '';

    if (clean.isEmpty) {
      return null;
    }

    final parsed = double.tryParse(
      clean,
    );

    if (parsed == null || parsed <= 0) {
      return 'Must be greater than 0';
    }

    return null;
  }

  String? _positiveNumber(
    String? value,
  ) {
    final parsed = double.tryParse(
      value?.trim() ?? '',
    );

    if (parsed == null || parsed <= 0) {
      return 'Must be greater than 0';
    }

    return null;
  }

  String? _metadataValidator(
    String? value,
  ) {
    final clean = value?.trim() ?? '';

    if (clean.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(
        clean,
      );

      if (decoded is! Map) {
        return 'Metadata must be a JSON object';
      }

      return null;
    } catch (_) {
      return 'Invalid JSON';
    }
  }

  Map<String, dynamic> _readMetadata() {
    final clean = _metadataController.text.trim();

    if (clean.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(
      clean,
    );

    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded,
      );
    }

    return {};
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final input = ControlledFormRenderFieldInput(
      renderProfileId: widget.renderProfileId,
      mappingKey: _mappingKeyController.text.trim(),
      label: _labelController.text.trim().isEmpty
          ? null
          : _labelController.text.trim(),
      pageNumber: int.parse(
        _pageController.text.trim(),
      ),
      sourceScope: _sourceScope,
      sourceKey:
          _sourceScope == 'static' ? null : _sourceKeyController.text.trim(),
      staticValue:
          _sourceScope == 'static' ? _staticValueController.text : null,
      widgetType: _widgetType,
      xPoints: double.parse(
        _xController.text.trim(),
      ),
      yPoints: double.parse(
        _yController.text.trim(),
      ),
      widthPoints: _widthController.text.trim().isEmpty
          ? null
          : double.parse(
              _widthController.text.trim(),
            ),
      heightPoints: _heightController.text.trim().isEmpty
          ? null
          : double.parse(
              _heightController.text.trim(),
            ),
      fontSizePoints: double.parse(
        _fontSizeController.text.trim(),
      ),
      fontName: _fontName,
      textAlign: _textAlign,
      maxLines: int.parse(
        _maxLinesController.text.trim(),
      ),
      allowWrap: _allowWrap,
      requiredForRender: _requiredForRender,
      checkboxTrueValue: _checkboxTrueController.text.trim().isEmpty
          ? 'true'
          : _checkboxTrueController.text.trim(),
      checkboxMark: _checkboxMarkController.text.trim().isEmpty
          ? 'X'
          : _checkboxMarkController.text.trim(),
      prefixText:
          _prefixController.text.trim().isEmpty ? null : _prefixController.text,
      suffixText:
          _suffixController.text.trim().isEmpty ? null : _suffixController.text,
      dateFormat: _dateFormatController.text.trim().isEmpty
          ? 'dd/MM/yyyy'
          : _dateFormatController.text.trim(),
      metadata: _readMetadata(),
    );

    Navigator.of(context).pop(
      input,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 24,
      ),
      title: Text(
        _editing ? 'Edit PDF Field Mapping' : 'Add PDF Field Mapping',
      ),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              right: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  context,
                  'Mapping Identity',
                ),
                const SizedBox(
                  height: 10,
                ),
                TextFormField(
                  controller: _mappingKeyController,
                  readOnly: _editing,
                  validator: _requiredText,
                  decoration: InputDecoration(
                    labelText: 'Mapping Key',
                    hintText: 'patient_full_name',
                    helperText: _editing
                        ? 'Mapping key cannot be changed after creation.'
                        : 'Unique internal key for this PDF field.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Display Label',
                    hintText: 'Patient Full Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 22,
                ),
                _sectionTitle(
                  context,
                  'Data Source',
                ),
                const SizedBox(
                  height: 10,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _sourceScope,
                  decoration: const InputDecoration(
                    labelText: 'Source Scope',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'form_value',
                      child: Text(
                        'Form Value',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'patient',
                      child: Text(
                        'Patient',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'admission',
                      child: Text(
                        'Admission',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'instance',
                      child: Text(
                        'Form Instance',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'signature',
                      child: Text(
                        'Signature',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'static',
                      child: Text(
                        'Static Value',
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _sourceScope = value;
                    });
                  },
                ),
                const SizedBox(
                  height: 12,
                ),
                if (_sourceScope == 'static')
                  TextFormField(
                    controller: _staticValueController,
                    validator: _requiredText,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Static Value',
                      hintText: 'Text always printed on this mapping',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  TextFormField(
                    controller: _sourceKeyController,
                    validator: _requiredText,
                    decoration: InputDecoration(
                      labelText: 'Source Key',
                      hintText: _sourceHint(
                        _sourceScope,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(
                  height: 22,
                ),
                _sectionTitle(
                  context,
                  'PDF Position',
                ),
                const SizedBox(
                  height: 10,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(
                      alpha: 0.06,
                    ),
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                    border: Border.all(
                      color: Colors.blue.withValues(
                        alpha: 0.20,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Visual Coordinate Picker',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        'Open the exact official PDF and click '
                        'where this field must render.',
                        style: TextStyle(
                          color: context.cTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _openingCalibration
                              ? null
                              : _pickVisualCoordinate,
                          icon: _openingCalibration
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location_outlined,
                                ),
                          label: Text(
                            _openingCalibration
                                ? 'Opening PDF...'
                                : 'Pick Position on PDF',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                TextFormField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  validator: _positiveInteger,
                  decoration: const InputDecoration(
                    labelText: 'PDF Page Number',
                    helperText: 'Filled automatically by visual calibration.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _xController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _coordinate,
                        decoration: const InputDecoration(
                          labelText: 'X Points',
                          helperText: 'Bottom-left PDF origin',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _yController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _coordinate,
                        decoration: const InputDecoration(
                          labelText: 'Y Points',
                          helperText: 'Bottom-left PDF origin',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _widthController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _optionalPositiveNumber,
                        decoration: const InputDecoration(
                          labelText: 'Width Points',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _heightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _optionalPositiveNumber,
                        decoration: const InputDecoration(
                          labelText: 'Height Points',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 22,
                ),
                _sectionTitle(
                  context,
                  'Rendering',
                ),
                const SizedBox(
                  height: 10,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _widgetType,
                  decoration: const InputDecoration(
                    labelText: 'Widget Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'text',
                      child: Text(
                        'Text',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'multiline_text',
                      child: Text(
                        'Multiline Text',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'checkbox',
                      child: Text(
                        'Checkbox',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'radio',
                      child: Text(
                        'Radio',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'date',
                      child: Text(
                        'Date',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'signature_text',
                      child: Text(
                        'Signature Text',
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _widgetType = value;

                      if (value == 'multiline_text') {
                        _allowWrap = true;

                        final currentLines = int.tryParse(
                          _maxLinesController.text,
                        );

                        if (currentLines == null || currentLines < 2) {
                          _maxLinesController.text = '4';
                        }
                      }
                    });
                  },
                ),
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _fontName,
                        decoration: const InputDecoration(
                          labelText: 'Font',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Helvetica',
                            child: Text(
                              'Helvetica',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Times-Roman',
                            child: Text(
                              'Times Roman',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Courier',
                            child: Text(
                              'Courier',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _fontName = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _fontSizeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _positiveNumber,
                        decoration: const InputDecoration(
                          labelText: 'Font Size (pt)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 12,
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _textAlign,
                        decoration: const InputDecoration(
                          labelText: 'Text Alignment',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'left',
                            child: Text(
                              'Left',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'center',
                            child: Text(
                              'Center',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'right',
                            child: Text(
                              'Right',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _textAlign = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _maxLinesController,
                        keyboardType: TextInputType.number,
                        validator: _positiveInteger,
                        decoration: const InputDecoration(
                          labelText: 'Max Lines',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 8,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowWrap,
                  onChanged: (value) {
                    setState(() {
                      _allowWrap = value;
                    });
                  },
                  title: const Text(
                    'Allow text wrapping',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _requiredForRender,
                  onChanged: (value) {
                    setState(() {
                      _requiredForRender = value;
                    });
                  },
                  title: const Text(
                    'Required for official render',
                  ),
                  subtitle: const Text(
                    'Rendering must fail if this required value is missing.',
                  ),
                ),
                if (_widgetType == 'checkbox' || _widgetType == 'radio') ...[
                  const SizedBox(
                    height: 12,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _checkboxTrueController,
                          decoration: const InputDecoration(
                            labelText: 'True / Match Value',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _checkboxMarkController,
                          decoration: const InputDecoration(
                            labelText: 'Printed Mark',
                            hintText: 'X',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_widgetType == 'date') ...[
                  const SizedBox(
                    height: 12,
                  ),
                  TextFormField(
                    controller: _dateFormatController,
                    decoration: const InputDecoration(
                      labelText: 'Date Format',
                      hintText: 'dd/MM/yyyy',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(
                  height: 22,
                ),
                _sectionTitle(
                  context,
                  'Optional Formatting',
                ),
                const SizedBox(
                  height: 10,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _prefixController,
                        decoration: const InputDecoration(
                          labelText: 'Prefix',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _suffixController,
                        decoration: const InputDecoration(
                          labelText: 'Suffix',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 22,
                ),
                _sectionTitle(
                  context,
                  'Advanced Metadata',
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'Use this only for advanced mappings such as '
                  'AcroForm field names, radio values or signature filters.',
                  style: TextStyle(
                    color: context.cTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                TextFormField(
                  controller: _metadataController,
                  validator: _metadataValidator,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Metadata JSON',
                    hintText: '{\n  "acroform_field_name": "PatientName"\n}',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: CorviaColors.warning.withValues(
                      alpha: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Text(
                    'The visual picker helps measure the position, '
                    'but every mapping still needs to be checked '
                    'against the exact controlled PDF before approval.',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _openingCalibration
              ? null
              : () {
                  Navigator.of(context).pop();
                },
          child: const Text(
            'Cancel',
          ),
        ),
        FilledButton.icon(
          onPressed: _openingCalibration ? null : _submit,
          icon: const Icon(
            Icons.save_outlined,
          ),
          label: Text(
            _editing ? 'Save Changes' : 'Add Mapping',
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title,
  ) {
    return Text(
      title,
      style: TextStyle(
        color: context.cTextPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  String _sourceHint(
    String sourceScope,
  ) {
    switch (sourceScope) {
      case 'form_value':
        return 'e.g. consent_given';

      case 'patient':
        return 'e.g. full_name or id_number';

      case 'admission':
        return 'e.g. admission_number';

      case 'instance':
        return 'e.g. finalized_at';

      case 'signature':
        return 'e.g. signer_name';

      default:
        return 'Source key';
    }
  }
}
