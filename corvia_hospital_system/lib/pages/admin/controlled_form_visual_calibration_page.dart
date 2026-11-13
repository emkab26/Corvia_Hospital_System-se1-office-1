import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/controlled_form_service.dart';

class ControlledFormPdfCoordinateSelection {
  const ControlledFormPdfCoordinateSelection({
    required this.pageNumber,
    required this.xPoints,
    required this.yPoints,
    this.widthPoints,
    this.heightPoints,
  });

  final int pageNumber;

  final double xPoints;
  final double yPoints;

  final double? widthPoints;
  final double? heightPoints;
}

class ControlledFormVisualCalibrationPage extends StatefulWidget {
  const ControlledFormVisualCalibrationPage({
    super.key,
    required this.registry,
    required this.version,
    this.initialPageNumber,
    this.initialXPoints,
    this.initialYPoints,
    this.initialWidthPoints,
    this.initialHeightPoints,
  });

  final ControlledFormRegistryRecord registry;
  final ControlledFormVersionRecord version;

  final int? initialPageNumber;

  final double? initialXPoints;
  final double? initialYPoints;

  final double? initialWidthPoints;
  final double? initialHeightPoints;

  @override
  State<ControlledFormVisualCalibrationPage> createState() {
    return _ControlledFormVisualCalibrationPageState();
  }
}

class _ControlledFormVisualCalibrationPageState
    extends State<ControlledFormVisualCalibrationPage> {
  static const double _rasterDpi = 96.0;
  static const double _pdfPointsPerInch = 72.0;

  final ControlledFormService _service = ControlledFormService();

  final TextEditingController _xController = TextEditingController();

  final TextEditingController _yController = TextEditingController();

  final TextEditingController _widthController = TextEditingController();

  final TextEditingController _heightController = TextEditingController();

  bool _loading = true;

  String? _error;

  List<_CalibrationPdfPage> _pages = const [];

  int _pageIndex = 0;

  Offset? _markerNormalised;

  @override
  void initState() {
    super.initState();

    _initialiseControllers();
    _loadOfficialPdf();
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();

    super.dispose();
  }

  void _initialiseControllers() {
    final x = widget.initialXPoints;
    final y = widget.initialYPoints;
    final width = widget.initialWidthPoints;
    final height = widget.initialHeightPoints;

    if (x != null) {
      _xController.text = _formatNumber(
        x,
      );
    }

    if (y != null) {
      _yController.text = _formatNumber(
        y,
      );
    }

    if (width != null) {
      _widthController.text = _formatNumber(
        width,
      );
    }

    if (height != null) {
      _heightController.text = _formatNumber(
        height,
      );
    }
  }

  Future<void> _loadOfficialPdf() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      if (!widget.version.hasUploadedSource) {
        throw const ControlledFormException(
          'This controlled version does not have an uploaded '
          'official PDF master.',
        );
      }

      final pdfBytes = await _service.downloadOfficialPdf(
        version: widget.version,
      );

      if (pdfBytes.isEmpty) {
        throw const ControlledFormException(
          'The official PDF master is empty.',
        );
      }

      final pages = <_CalibrationPdfPage>[];

      await for (final raster in Printing.raster(
        pdfBytes,
        dpi: _rasterDpi,
      )) {
        final pngBytes = await raster.toPng();

        pages.add(
          _CalibrationPdfPage(
            widthPixels: raster.width,
            heightPixels: raster.height,
            pngBytes: pngBytes,
          ),
        );
      }

      if (pages.isEmpty) {
        throw const ControlledFormException(
          'Corvia could not rasterise any pages from '
          'the official PDF master.',
        );
      }

      var pageIndex = (widget.initialPageNumber ?? 1) - 1;

      if (pageIndex < 0) {
        pageIndex = 0;
      }

      if (pageIndex >= pages.length) {
        pageIndex = pages.length - 1;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _pages = pages;
        _pageIndex = pageIndex;
        _loading = false;
      });

      _syncMarkerFromCoordinates();
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

  _CalibrationPdfPage? get _currentPage {
    if (_pages.isEmpty) {
      return null;
    }

    if (_pageIndex < 0 || _pageIndex >= _pages.length) {
      return null;
    }

    return _pages[_pageIndex];
  }

  double get _currentPageWidthPoints {
    final page = _currentPage;

    if (page == null) {
      return 0;
    }

    return page.widthPixels * _pdfPointsPerInch / _rasterDpi;
  }

  double get _currentPageHeightPoints {
    final page = _currentPage;

    if (page == null) {
      return 0;
    }

    return page.heightPixels * _pdfPointsPerInch / _rasterDpi;
  }

  void _selectPage(
    int newIndex,
  ) {
    if (newIndex < 0 || newIndex >= _pages.length || newIndex == _pageIndex) {
      return;
    }

    setState(() {
      _pageIndex = newIndex;

      /*
       * Coordinates are page-specific.
       *
       * When the admin changes page we clear the X/Y anchor
       * so a coordinate from another page cannot accidentally
       * be saved against this page.
       */
      _markerNormalised = null;

      _xController.clear();
      _yController.clear();
    });
  }

  void _previousPage() {
    _selectPage(
      _pageIndex - 1,
    );
  }

  void _nextPage() {
    _selectPage(
      _pageIndex + 1,
    );
  }

  void _handlePdfTap({
    required TapDownDetails details,
    required Size displaySize,
  }) {
    final page = _currentPage;

    if (page == null || displaySize.width <= 0 || displaySize.height <= 0) {
      return;
    }

    final localX = details.localPosition.dx
        .clamp(
          0.0,
          displaySize.width,
        )
        .toDouble();

    final localY = details.localPosition.dy
        .clamp(
          0.0,
          displaySize.height,
        )
        .toDouble();

    final normalisedX = localX / displaySize.width;

    final normalisedTopY = localY / displaySize.height;

    final xPoints = normalisedX * _currentPageWidthPoints;

    /*
     * Flutter/image coordinates start top-left.
     *
     * PDF coordinates start bottom-left, therefore Y must
     * be inverted.
     */
    final yPoints =
        _currentPageHeightPoints - (normalisedTopY * _currentPageHeightPoints);

    setState(() {
      _xController.text = _formatNumber(
        xPoints,
      );

      _yController.text = _formatNumber(
        yPoints,
      );

      _markerNormalised = Offset(
        normalisedX,
        normalisedTopY,
      );
    });
  }

  void _syncMarkerFromCoordinates() {
    final page = _currentPage;

    if (page == null) {
      return;
    }

    final x = double.tryParse(
      _xController.text.trim(),
    );

    final y = double.tryParse(
      _yController.text.trim(),
    );

    if (x == null ||
        y == null ||
        _currentPageWidthPoints <= 0 ||
        _currentPageHeightPoints <= 0) {
      if (mounted) {
        setState(() {
          _markerNormalised = null;
        });
      }

      return;
    }

    final normalisedX = x / _currentPageWidthPoints;

    final normalisedTopY = 1 - (y / _currentPageHeightPoints);

    if (normalisedX < 0 ||
        normalisedX > 1 ||
        normalisedTopY < 0 ||
        normalisedTopY > 1) {
      if (mounted) {
        setState(() {
          _markerNormalised = null;
        });
      }

      return;
    }

    if (mounted) {
      setState(() {
        _markerNormalised = Offset(
          normalisedX,
          normalisedTopY,
        );
      });
    }
  }

  void _nudgeX(
    double change,
  ) {
    final current = double.tryParse(
      _xController.text.trim(),
    );

    if (current == null) {
      return;
    }

    final next = (current + change).clamp(
      0.0,
      _currentPageWidthPoints,
    );

    _xController.text = _formatNumber(
      next,
    );

    _syncMarkerFromCoordinates();
  }

  void _nudgeY(
    double change,
  ) {
    final current = double.tryParse(
      _yController.text.trim(),
    );

    if (current == null) {
      return;
    }

    final next = (current + change).clamp(
      0.0,
      _currentPageHeightPoints,
    );

    _yController.text = _formatNumber(
      next,
    );

    _syncMarkerFromCoordinates();
  }

  void _clearSelection() {
    setState(() {
      _markerNormalised = null;

      _xController.clear();
      _yController.clear();

      _widthController.clear();
      _heightController.clear();
    });
  }

  void _useCoordinate() {
    final page = _currentPage;

    if (page == null) {
      return;
    }

    final x = double.tryParse(
      _xController.text.trim(),
    );

    final y = double.tryParse(
      _yController.text.trim(),
    );

    if (x == null || y == null) {
      _showMessage(
        'Click a position on the official PDF first.',
        isError: true,
      );

      return;
    }

    final width = _widthController.text.trim().isEmpty
        ? null
        : double.tryParse(
            _widthController.text.trim(),
          );

    final height = _heightController.text.trim().isEmpty
        ? null
        : double.tryParse(
            _heightController.text.trim(),
          );

    if (x < 0 || x > _currentPageWidthPoints) {
      _showMessage(
        'X is outside the current PDF page.',
        isError: true,
      );

      return;
    }

    if (y < 0 || y > _currentPageHeightPoints) {
      _showMessage(
        'Y is outside the current PDF page.',
        isError: true,
      );

      return;
    }

    if (width != null && width <= 0) {
      _showMessage(
        'Width must be greater than zero.',
        isError: true,
      );

      return;
    }

    if (height != null && height <= 0) {
      _showMessage(
        'Height must be greater than zero.',
        isError: true,
      );

      return;
    }

    if (width != null && x + width > _currentPageWidthPoints + 0.01) {
      _showMessage(
        'The selected width extends past the right '
        'edge of the PDF page.',
        isError: true,
      );

      return;
    }

    if (height != null && y + height > _currentPageHeightPoints + 0.01) {
      _showMessage(
        'The selected height extends past the top '
        'edge of the PDF page.',
        isError: true,
      );

      return;
    }

    Navigator.of(context).pop(
      ControlledFormPdfCoordinateSelection(
        pageNumber: _pageIndex + 1,
        xPoints: x,
        yPoints: y,
        widthPoints: width,
        heightPoints: height,
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
          backgroundColor: isError ? Colors.red.shade700 : null,
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

    return error.toString().replaceFirst(
          'Exception: ',
          '',
        );
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PDF Coordinate Calibration',
        ),
        actions: [
          IconButton(
            tooltip: 'Reload Official PDF',
            onPressed: _loading ? null : _loadOfficialPdf,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(
              height: 14,
            ),
            Text(
              'Loading official PDF master...',
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_pages.isEmpty) {
      return const Center(
        child: Text(
          'No PDF pages available.',
        ),
      );
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
              Expanded(
                child: _buildPdfPanel(),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).dividerColor,
              ),
              SizedBox(
                width: 360,
                child: _buildControlPanel(),
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(
            16,
          ),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(
                    context,
                  ).height *
                  0.65,
              child: _buildPdfPanel(),
            ),
            const SizedBox(
              height: 16,
            ),
            _buildControlPanel(),
          ],
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 600,
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(
                24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 58,
                    color: Colors.red,
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                  const Text(
                    'Official PDF could not load',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Text(
                    _error ?? 'Unknown PDF error.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  FilledButton.icon(
                    onPressed: _loadOfficialPdf,
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
      ),
    );
  }

  Widget _buildPdfPanel() {
    final page = _currentPage;

    if (page == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.grey.shade900,
      child: Column(
        children: [
          _buildPdfToolbar(),
          Expanded(
            child: LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(
                    20,
                  ),
                  child: Center(
                    child: _buildInteractivePage(
                      page,
                      constraints,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfToolbar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      color: Colors.black.withValues(
        alpha: 0.35,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous Page',
            onPressed: _pageIndex <= 0 ? null : _previousPage,
            color: Colors.white,
            icon: const Icon(
              Icons.chevron_left,
            ),
          ),
          Text(
            'Page ${_pageIndex + 1} '
            'of ${_pages.length}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Next Page',
            onPressed: _pageIndex >= _pages.length - 1 ? null : _nextPage,
            color: Colors.white,
            icon: const Icon(
              Icons.chevron_right,
            ),
          ),
          const Spacer(),
          Text(
            '${_formatNumber(_currentPageWidthPoints)} × '
            '${_formatNumber(_currentPageHeightPoints)} pt',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractivePage(
    _CalibrationPdfPage page,
    BoxConstraints constraints,
  ) {
    final availableWidth = math.max(
      260.0,
      constraints.maxWidth - 50,
    );

    final displayWidth = math.min(
      availableWidth,
      900.0,
    );

    final aspectRatio = page.widthPixels / page.heightPixels;

    final displayHeight = displayWidth / aspectRatio;

    final displaySize = Size(
      displayWidth,
      displayHeight,
    );

    return Column(
      children: [
        Text(
          'Click the exact anchor position on the official PDF',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (
            details,
          ) {
            _handlePdfTap(
              details: details,
              displaySize: displaySize,
            );
          },
          child: Container(
            width: displayWidth,
            height: displayHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  color: Colors.black45,
                ),
              ],
              border: Border.all(
                color: Colors.white24,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Image.memory(
                    page.pngBytes,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                if (_markerNormalised != null)
                  _buildCoordinateMarker(
                    displaySize,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        const Text(
          'Fine-tune the result with the X/Y controls on the right.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinateMarker(
    Size displaySize,
  ) {
    final marker = _markerNormalised!;

    final left = marker.dx * displaySize.width;

    final top = marker.dy * displaySize.height;

    const markerSize = 26.0;

    return Positioned(
      left: left - markerSize / 2,
      top: top - markerSize / 2,
      child: IgnorePointer(
        child: SizedBox(
          width: markerSize,
          height: markerSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red,
                    width: 2,
                  ),
                  color: Colors.white.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: markerSize,
                color: Colors.red,
              ),
              Container(
                width: markerSize,
                height: 2,
                color: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(
          18,
        ),
        children: [
          _buildMasterInfo(),
          const SizedBox(
            height: 20,
          ),
          _buildPageSelector(),
          const SizedBox(
            height: 20,
          ),
          _buildCoordinateSection(),
          const SizedBox(
            height: 20,
          ),
          _buildSizeSection(),
          const SizedBox(
            height: 20,
          ),
          _buildCoordinateSummary(),
          const SizedBox(
            height: 22,
          ),
          FilledButton.icon(
            onPressed: _markerNormalised == null ? null : _useCoordinate,
            icon: const Icon(
              Icons.check,
            ),
            label: const Text(
              'Use Coordinate',
            ),
          ),
          const SizedBox(
            height: 9,
          ),
          OutlinedButton.icon(
            onPressed: _markerNormalised == null && _xController.text.isEmpty
                ? null
                : _clearSelection,
            icon: const Icon(
              Icons.clear,
            ),
            label: const Text(
              'Clear Selection',
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          _buildSafetyNote(),
        ],
      ),
    );
  }

  Widget _buildMasterInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Official Master',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          widget.registry.officialFormName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          'Version '
          '${widget.version.versionNumber} '
          '• ${widget.version.versionLabel}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.version.officialFormNumber != null) ...[
          const SizedBox(
            height: 3,
          ),
          Text(
            'Official No: '
            '${widget.version.officialFormNumber}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildPageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PDF Page',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        DropdownButtonFormField<int>(
          initialValue: _pageIndex,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: List.generate(
            _pages.length,
            (index) {
              return DropdownMenuItem<int>(
                value: index,
                child: Text(
                  'Page ${index + 1}',
                ),
              );
            },
          ),
          onChanged: (value) {
            if (value == null) {
              return;
            }

            _selectPage(
              value,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCoordinateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Anchor Position',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          'PDF points, bottom-left origin.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(
          height: 10,
        ),
        TextField(
          controller: _xController,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          onChanged: (_) {
            _syncMarkerFromCoordinates();
          },
          decoration: const InputDecoration(
            labelText: 'X Points',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        _buildNudgeRow(
          label: 'Fine X',
          onMinusLarge: () {
            _nudgeX(
              -1,
            );
          },
          onMinusSmall: () {
            _nudgeX(
              -0.25,
            );
          },
          onPlusSmall: () {
            _nudgeX(
              0.25,
            );
          },
          onPlusLarge: () {
            _nudgeX(
              1,
            );
          },
        ),
        const SizedBox(
          height: 12,
        ),
        TextField(
          controller: _yController,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          onChanged: (_) {
            _syncMarkerFromCoordinates();
          },
          decoration: const InputDecoration(
            labelText: 'Y Points',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        _buildNudgeRow(
          label: 'Fine Y',
          onMinusLarge: () {
            _nudgeY(
              -1,
            );
          },
          onMinusSmall: () {
            _nudgeY(
              -0.25,
            );
          },
          onPlusSmall: () {
            _nudgeY(
              0.25,
            );
          },
          onPlusLarge: () {
            _nudgeY(
              1,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNudgeRow({
    required String label,
    required VoidCallback onMinusLarge,
    required VoidCallback onMinusSmall,
    required VoidCallback onPlusSmall,
    required VoidCallback onPlusLarge,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(
          height: 5,
        ),
        Row(
          children: [
            Expanded(
              child: _nudgeButton(
                '-1',
                onMinusLarge,
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: _nudgeButton(
                '-0.25',
                onMinusSmall,
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: _nudgeButton(
                '+0.25',
                onPlusSmall,
              ),
            ),
            const SizedBox(
              width: 5,
            ),
            Expanded(
              child: _nudgeButton(
                '+1',
                onPlusLarge,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nudgeButton(
    String text,
    VoidCallback onPressed,
  ) {
    return OutlinedButton(
      onPressed: _xController.text.isEmpty && _yController.text.isEmpty
          ? null
          : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 8,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Optional Field Box',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          'Useful for wrapping, alignment and multiline fields.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(
          height: 10,
        ),
        TextField(
          controller: _widthController,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Width Points',
            hintText: 'Optional',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        TextField(
          controller: _heightController,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Height Points',
            hintText: 'Optional',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinateSummary() {
    final x = _xController.text.trim();

    final y = _yController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
        borderRadius: BorderRadius.circular(
          12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected Coordinate',
            style: TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          SelectableText(
            x.isEmpty || y.isEmpty
                ? 'No position selected'
                : 'Page ${_pageIndex + 1}\n'
                    'X: $x pt\n'
                    'Y: $y pt',
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(
          12,
        ),
        border: Border.all(
          color: Colors.orange.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: const Text(
        'This screen helps measure the official PDF. '
        'The final mapping still needs review before approval. '
        'Changing the official master PDF requires a separate '
        'mapping revision.',
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class _CalibrationPdfPage {
  const _CalibrationPdfPage({
    required this.widthPixels,
    required this.heightPixels,
    required this.pngBytes,
  });

  final int widthPixels;
  final int heightPixels;

  final Uint8List pngBytes;
}
