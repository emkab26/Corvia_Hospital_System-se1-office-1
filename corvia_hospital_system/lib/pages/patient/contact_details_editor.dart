import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/validation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_format.dart';

/// A patient's address and phone number, read-only until they tap Edit details.
///
/// The fields used to be live text boxes on the Profile page, so a stray tap or
/// keystroke changed them (#240). Cancel puts back the saved values.
class ContactDetailsEditor extends StatefulWidget {
  const ContactDetailsEditor({
    super.key,
    required this.address,
    required this.phone,
    required this.onSave,
    this.onDirtyChanged,
    this.onSavingChanged,
    this.discardSignal,
  });

  /// The saved values. Shown read-only, and restored on Cancel.
  final String address;
  final String phone;

  /// Persists the edited values. Returns true when the save succeeded; the
  /// caller reports errors to the user.
  final Future<bool> Function(String address, String phone) onSave;

  /// Reports whether the fields differ from the saved values, so the page can
  /// warn before leaving with unsaved changes.
  final ValueChanged<bool>? onDirtyChanged;

  /// Lets the host prevent navigation while persistence is in progress.
  final ValueChanged<bool>? onSavingChanged;

  /// Fires when the host leaves the page (for example by switching dashboard
  /// tabs, which is not a route pop). Any edit in progress is cancelled so the
  /// form is not left half-edited for next time.
  final Listenable? discardSignal;

  @override
  State<ContactDetailsEditor> createState() => _ContactDetailsEditorState();
}

class _ContactDetailsEditorState extends State<ContactDetailsEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _addressController = TextEditingController(text: widget.address);
  late final _phoneController = TextEditingController(text: widget.phone);

  bool _editing = false;
  bool _saving = false;
  bool _dirty = false;
  bool _resettingFields = false;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_updateDirty);
    _phoneController.addListener(_updateDirty);
    widget.discardSignal?.addListener(_discard);
  }

  @override
  void didUpdateWidget(ContactDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.discardSignal != widget.discardSignal) {
      oldWidget.discardSignal?.removeListener(_discard);
      widget.discardSignal?.addListener(_discard);
    }
    // A reload or a successful save delivers new saved values. Do not clobber
    // what the patient is typing.
    if (!_editing &&
        (oldWidget.address != widget.address ||
            oldWidget.phone != widget.phone)) {
      _resetFields();
    }
  }

  @override
  void dispose() {
    widget.discardSignal?.removeListener(_discard);
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _updateDirty() {
    if (_resettingFields) return;
    final dirty = _addressController.text != widget.address ||
        _phoneController.text != widget.phone;
    _setDirty(dirty);
  }

  void _setDirty(bool dirty) {
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
    widget.onDirtyChanged?.call(dirty);
  }

  void _resetFields() {
    _replaceFields(widget.address, widget.phone);
    _setDirty(false);
  }

  void _replaceFields(String address, String phone) {
    _resettingFields = true;
    try {
      _addressController.text = address;
      _phoneController.text = phone;
    } finally {
      _resettingFields = false;
    }
  }

  void _discard() {
    if (_editing && !_saving) {
      _cancel();
    }
  }

  void _cancel() {
    if (_saving) return;
    _resetFields();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (_saving || !_editing || !_dirty) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final address = _addressController.text.trim();
    final phone = _phoneController.text.trim();
    setState(() => _saving = true);
    widget.onSavingChanged?.call(true);
    try {
      final saved = await widget.onSave(address, phone);
      if (!mounted) return;
      if (saved) {
        // The trimmed payload can equal the existing saved values, so a parent
        // property update alone cannot be relied on to clear dirty state.
        _replaceFields(address, phone);
        _setDirty(false);
        setState(() => _editing = false);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        widget.onSavingChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _editing ? _buildForm() : _buildReadOnly();
  }

  Widget _buildReadOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadOnlyRow(
          icon: Icons.home_outlined,
          label: 'Address',
          value: widget.address,
        ),
        const SizedBox(height: 12),
        _ReadOnlyRow(
          icon: Icons.phone_outlined,
          label: 'Phone Number',
          value: widget.phone,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => setState(() => _editing = true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit details'),
          style: _buttonStyle,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              _ContactField(
                enabled: !_saving,
                controller: _addressController,
                label: 'Address',
                hint: 'Enter your residential address',
                icon: Icons.home_outlined,
                autofocus: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              _ContactField(
                enabled: !_saving,
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'e.g. 082 123 4567',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: ValidationService.validateSouthAfricanPhone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+(). -]')),
                  const SouthAfricanPhoneInputFormatter(),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : _cancel,
                style: _buttonStyle,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving || !_dirty ? null : _save,
                style: _buttonStyle,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static final _buttonStyle = ButtonStyle(
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 15)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final missing = value.trim().isEmpty;

    return Row(
      children: [
        Icon(icon, color: context.cAccentReadable, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: context.cTextSecondary, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                missing ? 'Not provided' : value,
                style: TextStyle(
                  color: missing ? context.cTextMuted : context.cTextPrimary,
                  fontWeight: FontWeight.w600,
                  fontStyle: missing ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactField extends StatelessWidget {
  const _ContactField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.autovalidateMode,
    this.validator,
    this.inputFormatters,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final AutovalidateMode? autovalidateMode;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextFormField(
      enabled: enabled,
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autovalidateMode: autovalidateMode,
      validator: validator,
      inputFormatters: inputFormatters,
      style: TextStyle(
        color: context.cTextPrimary,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: context.cAccentReadable,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: context.cBgPrimary,
        labelStyle: TextStyle(color: context.cTextSecondary),
        hintStyle: TextStyle(
          color: context.cTextSecondary.withValues(alpha: 0.65),
        ),
        prefixIcon: Icon(icon, color: context.cAccentReadable),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: border(context.cDivider),
        focusedBorder: border(context.cAccentReadable, 1.8),
        errorBorder: border(CorviaColors.danger),
        focusedErrorBorder: border(CorviaColors.danger, 1.8),
      ),
    );
  }
}
