import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/emergency_contact.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_number_format.dart';
import '../../widgets/status_view.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  static const String _storageKey = 'emergency_contacts';

  bool _loading = true;
  String? _error;
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? [];

      final contacts = raw.map((e) {
        final map = Map<String, dynamic>.from(jsonDecode(e));
        return EmergencyContact.fromMap(map);
      }).toList();

      // Sort: primary first, then by name
      contacts.sort((a, b) {
        if (a.isPrimary && !b.isPrimary) return -1;
        if (!a.isPrimary && b.isPrimary) return 1;
        return a.name.compareTo(b.name);
      });

      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('Emergency contacts load failed: $error');

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Your emergency contacts could not be loaded.';
      });
    }
  }

  Future<void> _persistContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = contacts.map((c) => jsonEncode(c.toMap())).toList();
    await prefs.setStringList(_storageKey, raw);
  }

  Future<void> _openContactForm({EmergencyContact? existing}) async {
    final result = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cBgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _EmergencyContactFormSheet(existing: existing),
    );

    if (result == null) return;
    await _saveContact(result);
  }

  Future<void> _saveContact(EmergencyContact contact) async {
    final updated = List<EmergencyContact>.from(_contacts);

    if (contact.id == null) {
      // New contact — generate a unique id from timestamp
      final newContact = contact.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      updated.add(newContact);
    } else {
      // Edit existing contact
      final index = updated.indexWhere((c) => c.id == contact.id);
      if (index != -1) updated[index] = contact;
    }

    updated.sort((a, b) {
      if (a.isPrimary && !b.isPrimary) return -1;
      if (!a.isPrimary && b.isPrimary) return 1;
      return a.name.compareTo(b.name);
    });

    try {
      await _persistContacts(updated);

      if (!mounted) return;
      setState(() => _contacts = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Emergency contact saved.')));
    } catch (error) {
      debugPrint('Emergency contact save failed: $error');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The emergency contact could not be saved. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('Remove ${contact.name} from your emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: CorviaColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final updated = _contacts.where((c) => c.id != contact.id).toList();

    try {
      await _persistContacts(updated);

      if (!mounted) return;
      setState(() => _contacts = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contact removed.')));
    } catch (error) {
      debugPrint('Emergency contact removal failed: $error');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The emergency contact could not be removed. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(title: const Text('Emergency Contacts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openContactForm(),
        tooltip: 'Add contact',
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return StatusView.loading(message: 'Loading emergency contacts...');
    }

    if (_error != null) {
      return StatusView.error(friendlyMessage: _error!, onRetry: _loadContacts);
    }

    if (_contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.contact_phone_outlined,
                color: context.cTextSecondary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No emergency contacts yet',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add at least one contact who should be reached in an emergency.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.cTextSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _openContactForm,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add emergency contact'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: _contacts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          return _ContactCard(
            contact: contact,
            onEdit: () => _openContactForm(existing: contact),
            onDelete: () => _deleteContact(contact),
          );
        },
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CorviaColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: CorviaColors.primaryDark,
            child: Icon(Icons.person, color: CorviaColors.accentLight),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.name,
                        style: TextStyle(
                          color: context.cTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (contact.isPrimary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CorviaColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Primary',
                          style: TextStyle(
                            color: CorviaColors.accentLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  contact.relationship,
                  style: TextStyle(color: context.cTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPhoneNumber(contact.phoneNumber),
                  style: TextStyle(color: context.cTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: Icon(Icons.edit_outlined, color: context.cTextSecondary),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline, color: CorviaColors.danger),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _EmergencyContactFormSheet extends StatefulWidget {
  const _EmergencyContactFormSheet({this.existing});

  final EmergencyContact? existing;

  @override
  State<_EmergencyContactFormSheet> createState() =>
      _EmergencyContactFormSheetState();
}

class _EmergencyContactFormSheetState
    extends State<_EmergencyContactFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _relationshipCtrl;
  late final TextEditingController _phoneCtrl;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _relationshipCtrl = TextEditingController(
      text: existing?.relationship ?? '',
    );
    _phoneCtrl = TextEditingController(
      text: formatPhoneNumber(existing?.phoneNumber ?? ''),
    );
    _isPrimary = existing?.isPrimary ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _relationshipCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final result = EmergencyContact(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      relationship: _relationshipCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      isPrimary: _isPrimary,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing ? 'Edit Contact' : 'Add Emergency Contact',
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: context.cTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: EmergencyContactValidators.name,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _relationshipCtrl,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: context.cTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Relationship (e.g. Mother, Spouse)',
                  prefixIcon: Icon(Icons.diversity_3_outlined),
                ),
                validator: EmergencyContactValidators.relationship,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: const [SouthAfricanPhoneInputFormatter()],
                style: TextStyle(color: context.cTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '+27 82 123 4567',
                ),
                validator: EmergencyContactValidators.phoneNumber,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Set as primary contact',
                  style: TextStyle(color: context.cTextPrimary),
                ),
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(isEditing ? 'Save Changes' : 'Add Contact'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
