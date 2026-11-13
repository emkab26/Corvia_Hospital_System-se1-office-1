import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/blood_bank_service.dart';

/// A bounded, server-scoped search. Editing the query invalidates the selection.
class BloodBankPicker extends StatefulWidget {
  const BloodBankPicker(
      {super.key,
      required this.label,
      required this.load,
      required this.describe,
      required this.onSelected,
      required this.onDenied,
      this.hintText = 'Search by name or reference',
      this.helperText,
      this.enabled = true,
      this.minimumSearch = 2});
  final String label;
  final String hintText;
  final String? helperText;
  final Future<List<BloodBankRow>> Function(String) load;
  final String Function(BloodBankRow) describe;
  final ValueChanged<BloodBankRow?> onSelected;
  final ValueChanged<String> onDenied;
  final bool enabled;
  final int minimumSearch;
  @override
  State<BloodBankPicker> createState() => _BloodBankPickerState();
}

class _BloodBankPickerState extends State<BloodBankPicker> {
  final _controller = TextEditingController();
  final _field = GlobalKey<FormFieldState<BloodBankRow>>();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  List<BloodBankRow> _options = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.minimumSearch == 0) _search('');
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() {
      _options = [];
      _error = null;
      _loading = true;
    });
    try {
      final options = await widget.load(query.trim());
      if (!mounted || generation != _generation) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (BloodBankService.accessDenied(e)) {
        widget.onDenied(BloodBankService.message(e));
        return;
      }
      setState(() {
        _loading = false;
        _error = BloodBankService.message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => FormField<BloodBankRow>(
        key: _field,
        enabled: widget.enabled,
        validator: (value) => value == null
            ? 'Select a ${widget.label.toLowerCase()} from the results'
            : null,
        builder: (field) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
              controller: _controller,
              enabled: widget.enabled,
              maxLength: 100,
              decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hintText,
                  helperText: widget.helperText,
                  helperMaxLines: 3,
                  errorText: field.errorText,
                  suffixIcon: field.value == null
                      ? const Icon(Icons.search)
                      : const Icon(Icons.check_circle)),
              onChanged: (value) {
                _generation++;
                _debounce?.cancel();
                field.didChange(null);
                widget.onSelected(null);
                setState(() {
                  _options = [];
                  _error = null;
                  _loading = false;
                });
                if (value.trim().length >= widget.minimumSearch) {
                  _debounce = Timer(
                      const Duration(milliseconds: 350), () => _search(value));
                }
              }),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_loading &&
              _error == null &&
              field.value == null &&
              _options.isEmpty)
            Text(_controller.text.trim().length < widget.minimumSearch
                ? 'Enter at least ${widget.minimumSearch} characters.'
                : 'No eligible matches.'),
          if (_options.length == 25)
            const Text('First 25 matches. Refine your search if needed.'),
          if (_options.isNotEmpty)
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(shrinkWrap: true, children: [
                  for (final option in _options)
                    ListTile(
                        title: Text(widget.describe(option)),
                        onTap: !widget.enabled
                            ? null
                            : () {
                                _generation++;
                                _debounce?.cancel();
                                field.didChange(option);
                                widget.onSelected(option);
                                _controller.text = widget.describe(option);
                                setState(() {
                                  _options = [];
                                  _loading = false;
                                });
                              })
                ])),
          const SizedBox(height: 12),
        ]),
      );
}
