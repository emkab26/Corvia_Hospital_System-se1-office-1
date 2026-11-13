import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/nurse_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_controller_scope.dart';

class NurseLabCollectionPage extends StatefulWidget {
  const NurseLabCollectionPage({super.key, this.service, this.showAppBar = true});

  final NurseService? service;

  /// The nurse workspace supplies the shared header when this page is embedded.
  final bool showAppBar;

  @override
  State<NurseLabCollectionPage> createState() => _NurseLabCollectionPageState();
}

class _NurseLabCollectionPageState extends State<NurseLabCollectionPage> {
  static const List<String> _specimenTypes = [
    'Whole blood',
    'Serum',
    'Plasma',
    'Urine',
    'Stool',
    'Swab',
    'Sputum',
    'Tissue specimen',
    'Other',
  ];

  late final NurseService _service = widget.service ?? NurseService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isCollecting = false;
  String? _errorMessage;
  List<NurseLabCollectionOrder> _orders = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadQueue();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadQueue() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await _service.requireCurrentContext();
      final orders = await _service.loadLabCollectionQueue();

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanError(error);
      });
    }
  }

  List<NurseLabCollectionOrder> get _visibleOrders {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _orders;
    }

    return _orders.where((order) {
      return order.testName.toLowerCase().contains(query) ||
          order.labName.toLowerCase().contains(query) ||
          _patientName(order).toLowerCase().contains(query) ||
          _patientReference(order).toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _collect(NurseLabCollectionOrder order) async {
    if (_isCollecting) {
      return;
    }

    final details = await _showCollectionForm(order);
    if (details == null || !mounted) {
      return;
    }

    setState(() => _isCollecting = true);

    try {
      final collection = await _service.collectLabSpecimens(
        labResultId: order.labResultId,
        samples: details.samples,
        useTransportBag: details.useTransportBag,
        externalBagReference: details.externalBagReference,
        collectionNote: details.note,
      );

      if (!mounted) {
        return;
      }

      await _showCollectionLabels(order, collection);
      if (!mounted) {
        return;
      }

      await _loadQueue();
    } catch (error) {
      _showMessage(_cleanError(error));
    } finally {
      if (mounted) {
        setState(() => _isCollecting = false);
      }
    }
  }

  Future<_CollectionDetails?> _showCollectionForm(
    NurseLabCollectionOrder order,
  ) async {
    final samples = <_SampleDraft>[_SampleDraft()];
    var useTransportBag = false;

    return showDialog<_CollectionDetails>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (noteController) => TextControllerScope(
            builder: (externalBagController) => StatefulBuilder(
              builder: (context, setDialogState) {
                final samplesValid = samples.every(
                  (sample) =>
                      sample.specimenType != null &&
                      (!order.isOutsourced ||
                          sample.externalLabelReference.trim().isNotEmpty),
                );
                final bagValid = !useTransportBag ||
                    !order.isOutsourced ||
                    externalBagController.text.trim().isNotEmpty;

                return AlertDialog(
                  backgroundColor: context.cBgSecondary,
                  title: const Text('Collect specimens'),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoLine(
                              label: 'Patient', value: _patientName(order)),
                          _InfoLine(label: 'Test', value: order.testName),
                          _InfoLine(label: 'Destination', value: order.labName),
                          const SizedBox(height: 8),
                          _DestinationNotice(order: order),
                          const SizedBox(height: 18),
                          Text(
                            'Samples',
                            style: TextStyle(
                              color: context.cTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (var index = 0;
                              index < samples.length;
                              index++) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.cBgPrimary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.cDivider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Sample ${index + 1}',
                                          style: TextStyle(
                                            color: context.cTextPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (samples.length > 1)
                                        IconButton(
                                          tooltip: 'Remove sample',
                                          onPressed: () {
                                            setDialogState(
                                              () => samples.removeAt(index),
                                            );
                                          },
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey('type-${samples[index].key}'),
                                    initialValue: samples[index].specimenType,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Specimen type',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _specimenTypes
                                        .map(
                                          (type) => DropdownMenuItem(
                                            value: type,
                                            child: Text(type),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      setDialogState(
                                        () =>
                                            samples[index].specimenType = value,
                                      );
                                    },
                                  ),
                                  if (order.isOutsourced) ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      key: ValueKey(
                                        'external-${samples[index].key}',
                                      ),
                                      initialValue:
                                          samples[index].externalLabelReference,
                                      maxLength: 160,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'External lab label/reference',
                                        hintText:
                                            'Enter the label supplied by the external lab',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (value) {
                                        samples[index].externalLabelReference =
                                            value;
                                        setDialogState(() {});
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          OutlinedButton.icon(
                            onPressed: samples.length >= 10
                                ? null
                                : () {
                                    setDialogState(
                                      () => samples.add(_SampleDraft()),
                                    );
                                  },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add another sample'),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: useTransportBag,
                            title:
                                const Text('Place samples in a transport bag'),
                            subtitle: Text(
                              order.isOutsourced
                                  ? 'Use the bag and label supplied by the external laboratory.'
                                  : 'A separate Corvia QR label will be created for the bag.',
                            ),
                            onChanged: (value) {
                              setDialogState(() => useTransportBag = value);
                            },
                          ),
                          if (useTransportBag && order.isOutsourced) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: externalBagController,
                              maxLength: 160,
                              decoration: const InputDecoration(
                                labelText: 'External bag label/reference',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextField(
                            controller: noteController,
                            maxLength: 2000,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Collection note (optional)',
                              hintText:
                                  'Collection issue, condition, or handover note',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.isOutsourced
                                ? 'Corvia will not create or display QR labels for this outsourced collection. Use only the receiving laboratory’s supplied labels.'
                                : 'Every sample${useTransportBag ? ' and the transport bag' : ''} receives its own Corvia QR. QR content contains no patient information.',
                            style: TextStyle(
                              color: context.cTextSecondary,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: !samplesValid || !bagValid
                          ? null
                          : () {
                              Navigator.of(dialogContext).pop(
                                _CollectionDetails(
                                  samples: samples
                                      .map(
                                        (sample) => NurseSampleInput(
                                          specimenType: sample.specimenType!,
                                          externalLabelReference:
                                              sample.externalLabelReference,
                                        ),
                                      )
                                      .toList(),
                                  useTransportBag: useTransportBag,
                                  externalBagReference:
                                      externalBagController.text.trim(),
                                  note: noteController.text.trim(),
                                ),
                              );
                            },
                      icon: Icon(
                        order.isOutsourced
                            ? Icons.inventory_2_outlined
                            : Icons.qr_code_2_rounded,
                      ),
                      label: Text(
                        order.isOutsourced
                            ? 'Record collection'
                            : 'Create labels',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCollectionLabels(
    NurseLabCollectionOrder order,
    NurseSpecimenCollection collection,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dialogContext.cBgSecondary,
          title: Text(
            collection.isOutsourced
                ? 'External collection recorded'
                : 'Collection labels created',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InfoLine(label: 'Patient', value: _patientName(order)),
                  _InfoLine(label: 'Test', value: order.testName),
                  _InfoLine(label: 'Route to', value: collection.labName),
                  _InfoLine(
                    label: 'Service',
                    value: collection.isOutsourced
                        ? 'Outsourced laboratory'
                        : 'Internal hospital laboratory',
                  ),
                  const SizedBox(height: 14),
                  for (var index = 0;
                      index < collection.specimens.length;
                      index++) ...[
                    _CollectionLabelCard(
                      title:
                          'Sample ${index + 1} · ${collection.specimens[index].specimenType}',
                      code: collection.specimens[index].usesCorviaLabel
                          ? collection.specimens[index].containerCode
                          : collection.specimens[index].externalLabelReference,
                      qrPayload: collection.specimens[index].usesCorviaLabel
                          ? 'CORVIA_SPECIMEN|container_id=${collection.specimens[index].containerId}'
                          : null,
                      external: !collection.specimens[index].usesCorviaLabel,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (collection.bag != null) ...[
                    _CollectionLabelCard(
                      title: 'Transport bag',
                      code: collection.bag!.usesCorviaLabel
                          ? collection.bag!.bagCode
                          : collection.bag!.externalLabelReference,
                      qrPayload: collection.bag!.usesCorviaLabel
                          ? 'CORVIA_SPECIMEN_BAG|bag_id=${collection.bag!.bagId}'
                          : null,
                      external: !collection.bag!.usesCorviaLabel,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    collection.isOutsourced
                        ? 'No Corvia QR was generated. Confirm that every sample and the transport bag, when used, carry the external laboratory’s own labels before handover.'
                        : 'Attach the matching QR to every sample container and attach the separate bag QR when a transport bag is used.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: dialogContext.cTextSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  String _patientName(NurseLabCollectionOrder order) {
    return order.patientName;
  }

  String _patientReference(NurseLabCollectionOrder order) {
    return _firstText([
      order.patientNumber,
      order.patientId,
    ]);
  }

  String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceAll(')', '');

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final visibleOrders = _visibleOrders;

    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: widget.showAppBar ? AppBar(
        title: const Text('Specimen Collection'),
        actions: [
          IconButton(
            tooltip: 'Refresh queue',
            onPressed: _isLoading || _isCollecting ? null : _loadQueue,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ) : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: CorviaColors.accent))
          : _errorMessage != null
              ? _ErrorState(message: _errorMessage!, onRetry: _loadQueue)
              : RefreshIndicator(
                  color: context.cAccentReadable,
                  onRefresh: _loadQueue,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      _QueueSummary(
                        count: _orders.length,
                        outsourcedCount:
                            _orders.where((order) => order.isOutsourced).length,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _searchController.clear,
                                  icon: const Icon(Icons.clear_rounded),
                                ),
                          hintText:
                              'Search patient, record number, test, or laboratory',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (visibleOrders.isEmpty)
                        _EmptyQueue(
                            hasSearch: _searchController.text.isNotEmpty)
                      else
                        ...visibleOrders.expand(
                          (order) => [
                            _CollectionOrderCard(
                              order: order,
                              patientName: _patientName(order),
                              patientReference: _patientReference(order),
                              disabled: _isCollecting,
                              onCollect: () => _collect(order),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

class _CollectionDetails {
  const _CollectionDetails({
    required this.samples,
    required this.useTransportBag,
    required this.externalBagReference,
    required this.note,
  });

  final List<NurseSampleInput> samples;
  final bool useTransportBag;
  final String externalBagReference;
  final String note;
}

class _SampleDraft {
  _SampleDraft() : key = Object();

  final Object key;
  String? specimenType;
  String externalLabelReference = '';
}

class _CollectionLabelCard extends StatelessWidget {
  const _CollectionLabelCard({
    required this.title,
    required this.code,
    required this.qrPayload,
    required this.external,
  });

  final String title;
  final String code;
  final String? qrPayload;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (qrPayload != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrPayload!,
                size: 165,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            )
          else
            Icon(
              Icons.local_shipping_outlined,
              size: 42,
              color: CorviaColors.warning,
            ),
          const SizedBox(height: 10),
          Text(
            external ? 'External label: $code' : code,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.cTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: external ? 0 : 0.7,
            ),
          ),
          if (external) ...[
            const SizedBox(height: 4),
            Text(
              'Corvia QR intentionally not generated',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 86,
              child: Text(
                label,
                style: TextStyle(color: context.cTextSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _QueueSummary extends StatelessWidget {
  const _QueueSummary({
    required this.count,
    required this.outsourcedCount,
  });
  final int count;
  final int outsourcedCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: CorviaColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CorviaColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count order${count == 1 ? '' : 's'} awaiting collection',
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Confirm the patient and create a QR-labelled specimen container.',
                    style:
                        TextStyle(color: context.cTextSecondary, fontSize: 12),
                  ),
                  if (outsourcedCount > 0) ...[
                    const SizedBox(height: 5),
                    Text(
                      '$outsourcedCount order${outsourcedCount == 1 ? '' : 's'} route${outsourcedCount == 1 ? 's' : ''} to an outsourced laboratory.',
                      style: TextStyle(
                        color: context.cAccentReadable,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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

class _CollectionOrderCard extends StatelessWidget {
  const _CollectionOrderCard({
    required this.order,
    required this.patientName,
    required this.patientReference,
    required this.disabled,
    required this.onCollect,
  });

  final NurseLabCollectionOrder order;
  final String patientName;
  final String patientReference;
  final bool disabled;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cBgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cDivider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CorviaColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.biotech_outlined,
                      color: context.cAccentReadable),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.testName,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Awaiting specimen collection',
                        style: TextStyle(
                            color: CorviaColors.warning, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoLine(label: 'Patient', value: patientName),
            if (patientReference.isNotEmpty)
              _InfoLine(label: 'Record', value: patientReference),
            const SizedBox(height: 5),
            _DestinationBadge(order: order),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: disabled ? null : onCollect,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Collect and label'),
              ),
            ),
          ],
        ),
      );
}

class _DestinationNotice extends StatelessWidget {
  const _DestinationNotice({required this.order});

  final NurseLabCollectionOrder order;

  @override
  Widget build(BuildContext context) {
    final color =
        order.isOutsourced ? CorviaColors.warning : context.cAccentReadable;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            order.isOutsourced
                ? Icons.local_shipping_outlined
                : Icons.local_hospital_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              order.isOutsourced
                  ? 'This specimen must be handed over for transport to ${order.labName}.'
                  : 'This specimen must be sent to ${order.labName} inside the hospital.',
              style: TextStyle(
                color: context.cTextSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationBadge extends StatelessWidget {
  const _DestinationBadge({required this.order});

  final NurseLabCollectionOrder order;

  @override
  Widget build(BuildContext context) {
    final color =
        order.isOutsourced ? CorviaColors.warning : context.cAccentReadable;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            order.isOutsourced
                ? Icons.local_shipping_outlined
                : Icons.local_hospital_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.isOutsourced
                      ? 'Outsourced laboratory'
                      : 'Internal laboratory',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.labName,
                  style: TextStyle(
                    color: context.cTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.hasSearch});
  final bool hasSearch;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 54, color: context.cTextSecondary),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No matching orders'
                  : 'No specimens awaiting collection',
              style: TextStyle(
                color: context.cTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              hasSearch
                  ? 'Try a different patient, record number, or test name.'
                  : 'New doctor orders will appear here when they are ready for collection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.cTextSecondary),
            ),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 54, color: CorviaColors.danger),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}
