import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class HospitalLocationsPage extends StatefulWidget {
  const HospitalLocationsPage({super.key});

  @override
  State<HospitalLocationsPage> createState() => _HospitalLocationsPageState();
}

class _HospitalLocationsPageState extends State<HospitalLocationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  Color get actionBackground =>
      context.isDarkTheme ? context.cBgSecondary : context.cTextPrimary;
  Color get primary => context.cTextPrimary;
  Color get accent => CorviaColors.accent;
  Color get success => CorviaColors.success;
  Color get warning => CorviaColors.warning;
  Color get error => CorviaColors.danger;
  Color get background => context.cBgPrimary;
  Color get textDark => context.cTextPrimary;
  Color get mutedText => context.cTextSecondary;

  bool _loading = true;
  String? _error;

  String? _hospitalId;
  String _hospitalName = 'Hospital Location';
  Map<String, dynamic> _hospital = {};

  @override
  void initState() {
    super.initState();
    _loadLocationPage();
  }

  Future<void> _loadLocationPage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('You are not signed in.');
      }

      final adminLink = await _supabase
          .from('hospital_admins')
          .select('hospital_id')
          .eq('profile_id', user.id)
          .maybeSingle();

      if (adminLink == null) {
        throw Exception(
          'This account is not linked to a hospital admin record.',
        );
      }

      final hospitalId = adminLink['hospital_id']?.toString();

      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('No hospital is linked to this admin account.');
      }

      final hospitalRow = await _supabase
          .from('hospitals')
          .select()
          .eq('id', hospitalId)
          .maybeSingle();

      if (hospitalRow == null) {
        throw Exception('Hospital record could not be found.');
      }

      _hospitalId = hospitalId;
      _hospital = Map<String, dynamic>.from(hospitalRow);

      _hospitalName = _valueFor([
        'name',
        'hospital_name',
      ], fallback: 'Hospital Location');
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _valueFor(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = _hospital[key];

      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    return fallback;
  }

  bool _setFirstExistingField(
    Map<String, dynamic> payload,
    List<String> possibleColumns,
    String value,
  ) {
    for (final column in possibleColumns) {
      if (_hospital.containsKey(column)) {
        payload[column] = value.trim().isEmpty ? null : value.trim();
        return true;
      }
    }

    return false;
  }

  double? _coordinateFor(List<String> keys) {
    for (final key in keys) {
      final value = _hospital[key];

      if (value == null) continue;

      if (value is num) {
        return value.toDouble();
      }

      final parsed = double.tryParse(value.toString());

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  String get _address {
    final street = _valueFor([
      'address',
      'street_address',
      'physical_address',
      'location',
    ]);

    final city = _valueFor(['city', 'town', 'suburb']);

    final province = _valueFor(['province', 'state', 'region']);

    final country = _valueFor(['country']);

    final postalCode = _valueFor(['postal_code', 'zip_code']);

    final parts = <String>[
      if (street.isNotEmpty) street,
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
      if (postalCode.isNotEmpty) postalCode,
      if (country.isNotEmpty) country,
    ];

    return parts.isEmpty ? 'No physical address captured.' : parts.join(', ');
  }

  String get _phone {
    return _valueFor([
      'phone',
      'phone_number',
      'contact_number',
      'hospital_phone',
    ], fallback: 'No phone number captured');
  }

  String get _email {
    return _valueFor([
      'email',
      'contact_email',
      'hospital_email',
    ], fallback: 'No email address captured');
  }

  String get _website {
    return _valueFor([
      'website',
      'website_url',
      'url',
    ], fallback: 'No website captured');
  }

  String get _openingHours {
    return _valueFor([
      'opening_hours',
      'operating_hours',
      'business_hours',
    ], fallback: 'Not captured');
  }

  String get _emergencyPhone {
    return _valueFor([
      'emergency_phone',
      'emergency_contact_number',
      'emergency_number',
    ], fallback: 'Not captured');
  }

  String get _latitude {
    final value = _coordinateFor(['latitude', 'lat']);

    return value == null ? 'Not captured' : value.toStringAsFixed(6);
  }

  String get _longitude {
    final value = _coordinateFor(['longitude', 'lng', 'lon']);

    return value == null ? 'Not captured' : value.toStringAsFixed(6);
  }

  bool get _hasCoordinates {
    return _coordinateFor(['latitude', 'lat']) != null &&
        _coordinateFor(['longitude', 'lng', 'lon']) != null;
  }

  bool get _hasAddress {
    return _address != 'No physical address captured.';
  }

  bool get _hasContact {
    return _phone != 'No phone number captured' ||
        _email != 'No email address captured';
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? error : actionBackground,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showHospitalEditor() async {
    final nameController = TextEditingController(text: _hospitalName);

    final addressController = TextEditingController(
      text: _valueFor([
        'address',
        'street_address',
        'physical_address',
        'location',
      ]),
    );

    final cityController = TextEditingController(
      text: _valueFor(['city', 'town', 'suburb']),
    );

    final provinceController = TextEditingController(
      text: _valueFor(['province', 'state', 'region']),
    );

    final countryController = TextEditingController(
      text: _valueFor(['country']),
    );

    final postalCodeController = TextEditingController(
      text: _valueFor(['postal_code', 'zip_code']),
    );

    final phoneController = TextEditingController(
      text: _valueFor([
        'phone',
        'phone_number',
        'contact_number',
        'hospital_phone',
      ]),
    );

    final emailController = TextEditingController(
      text: _valueFor(['email', 'contact_email', 'hospital_email']),
    );

    final emergencyPhoneController = TextEditingController(
      text: _valueFor([
        'emergency_phone',
        'emergency_contact_number',
        'emergency_number',
      ]),
    );

    final websiteController = TextEditingController(
      text: _valueFor(['website', 'website_url', 'url']),
    );

    final hoursController = TextEditingController(
      text: _valueFor(['opening_hours', 'operating_hours', 'business_hours']),
    );

    final latitudeController = TextEditingController(
      text: _coordinateFor(['latitude', 'lat'])?.toString() ?? '',
    );

    final longitudeController = TextEditingController(
      text: _coordinateFor(['longitude', 'lng', 'lon'])?.toString() ?? '',
    );

    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 860),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                decoration: BoxDecoration(
                  color: context.cBgSecondary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Hospital Location',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Only columns that already exist in your hospitals table will be updated.',
                        style: TextStyle(color: mutedText, fontSize: 13),
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: nameController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Hospital name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: addressController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Street address',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: cityController,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'City / Suburb',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: provinceController,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Province',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: countryController,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Country',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: postalCodeController,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Postal code',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        enabled: !saving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Hospital phone number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emergencyPhoneController,
                        enabled: !saving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Emergency phone number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        enabled: !saving,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Hospital email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: websiteController,
                        enabled: !saving,
                        decoration: const InputDecoration(
                          labelText: 'Website',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: hoursController,
                        enabled: !saving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Operating hours',
                          hintText: 'Example: Open 24 hours, 7 days a week',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: latitudeController,
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Latitude',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: longitudeController,
                              enabled: !saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Longitude',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final latitude = double.tryParse(
                                    latitudeController.text.trim(),
                                  );

                                  final longitude = double.tryParse(
                                    longitudeController.text.trim(),
                                  );

                                  if (latitudeController.text
                                          .trim()
                                          .isNotEmpty &&
                                      latitude == null) {
                                    _showSnack(
                                      'Latitude must be a valid number.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (longitudeController.text
                                          .trim()
                                          .isNotEmpty &&
                                      longitude == null) {
                                    _showSnack(
                                      'Longitude must be a valid number.',
                                      isError: true,
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    saving = true;
                                  });

                                  try {
                                    final payload = <String, dynamic>{};
                                    bool hasEditableUpdate = false;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'name',
                                          'hospital_name',
                                        ], nameController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'address',
                                          'street_address',
                                          'physical_address',
                                          'location',
                                        ], addressController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'city',
                                          'town',
                                          'suburb',
                                        ], cityController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'province',
                                          'state',
                                          'region',
                                        ], provinceController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'country',
                                        ], countryController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'postal_code',
                                          'zip_code',
                                        ], postalCodeController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'phone',
                                          'phone_number',
                                          'contact_number',
                                          'hospital_phone',
                                        ], phoneController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'emergency_phone',
                                          'emergency_contact_number',
                                          'emergency_number',
                                        ], emergencyPhoneController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'email',
                                          'contact_email',
                                          'hospital_email',
                                        ], emailController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'website',
                                          'website_url',
                                          'url',
                                        ], websiteController.text) ||
                                        hasEditableUpdate;

                                    hasEditableUpdate =
                                        _setFirstExistingField(payload, [
                                          'opening_hours',
                                          'operating_hours',
                                          'business_hours',
                                        ], hoursController.text) ||
                                        hasEditableUpdate;

                                    if (_hospital.containsKey('latitude')) {
                                      payload['latitude'] = latitude;
                                      hasEditableUpdate = true;
                                    } else if (_hospital.containsKey('lat')) {
                                      payload['lat'] = latitude;
                                      hasEditableUpdate = true;
                                    }

                                    if (_hospital.containsKey('longitude')) {
                                      payload['longitude'] = longitude;
                                      hasEditableUpdate = true;
                                    } else if (_hospital.containsKey('lng')) {
                                      payload['lng'] = longitude;
                                      hasEditableUpdate = true;
                                    } else if (_hospital.containsKey('lon')) {
                                      payload['lon'] = longitude;
                                      hasEditableUpdate = true;
                                    }

                                    if (!hasEditableUpdate) {
                                      throw Exception(
                                        'No compatible editable columns were found in the hospitals table.',
                                      );
                                    }

                                    if (_hospital.containsKey('updated_at')) {
                                      payload['updated_at'] = DateTime.now()
                                          .toUtc()
                                          .toIso8601String();
                                    }

                                    await _supabase
                                        .from('hospitals')
                                        .update(payload)
                                        .eq('id', _hospitalId!);

                                    if (sheetContext.mounted) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    await _loadLocationPage();

                                    _showSnack(
                                      'Hospital location details updated.',
                                    );
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }

                                    _showSnack(
                                      'Could not update hospital details: $e',
                                      isError: true,
                                    );
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.save_rounded),
                          label: Text(
                            saving ? 'Saving...' : 'Save location details',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: actionBackground,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
    cityController.dispose();
    provinceController.dispose();
    countryController.dispose();
    postalCodeController.dispose();
    phoneController.dispose();
    emailController.dispose();
    emergencyPhoneController.dispose();
    websiteController.dispose();
    hoursController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _showHospitalEditor,
        backgroundColor: actionBackground,
        foregroundColor: Colors.white,
        icon: Icon(Icons.edit_location_alt_rounded),
        label: Text('Manage Location'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadLocationPage,
          child: _loading
              ? Center(child: CircularProgressIndicator(color: accent))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_error != null) _buildErrorBox(),
                      _buildStatusCards(),
                      const SizedBox(height: 22),
                      _buildLocationPanel(),
                      const SizedBox(height: 22),
                      _buildContactPanel(),
                      const SizedBox(height: 22),
                      _buildCoordinatesPanel(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to hospital dashboard',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          color: primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location • $_hospitalName',
                style: TextStyle(
                  color: textDark,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Manage hospital location, contact information and operating details.',
                style: TextStyle(color: mutedText, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _loadLocationPage,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load all hospital location information. $_error',
              style: TextStyle(color: textDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    final cards = [
      _LocationStatusCard(
        title: 'Address',
        value: _hasAddress ? 'Captured' : 'Missing',
        subtitle: _hasAddress
            ? 'Physical location is available'
            : 'Add a physical hospital address',
        icon: Icons.location_on_rounded,
        color: _hasAddress ? success : warning,
      ),
      _LocationStatusCard(
        title: 'Contact',
        value: _hasContact ? 'Ready' : 'Missing',
        subtitle: _hasContact
            ? 'Phone or email is available'
            : 'Add hospital contact details',
        icon: Icons.contact_phone_rounded,
        color: _hasContact ? accent : warning,
      ),
      _LocationStatusCard(
        title: 'Coordinates',
        value: _hasCoordinates ? 'Ready' : 'Missing',
        subtitle: _hasCoordinates
            ? 'Map coordinates are available'
            : 'Add latitude and longitude',
        icon: Icons.my_location_rounded,
        color: _hasCoordinates ? success : warning,
      ),
      _LocationStatusCard(
        title: 'Emergency Contact',
        value: _emergencyPhone == 'Not captured' ? 'Missing' : 'Ready',
        subtitle: _emergencyPhone == 'Not captured'
            ? 'Add an emergency phone number'
            : 'Emergency contact number saved',
        icon: Icons.emergency_rounded,
        color: _emergencyPhone == 'Not captured' ? error : success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 4 : 2,
            mainAxisExtent: 205,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.cBgSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.cDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: card.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(card.icon, color: card.color),
                  ),
                  const Spacer(),
                  Text(
                    card.value,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    card.title,
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationPanel() {
    return _buildPanel(
      title: 'Hospital Location',
      icon: Icons.location_city_rounded,
      action: OutlinedButton.icon(
        onPressed: _showHospitalEditor,
        icon: Icon(Icons.edit_rounded, size: 18),
        label: Text('Edit'),
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.business_rounded,
            label: 'Hospital name',
            value: _hospitalName,
            color: primary,
          ),
          _buildInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Physical address',
            value: _address,
            color: accent,
          ),
          _buildInfoRow(
            icon: Icons.schedule_rounded,
            label: 'Operating hours',
            value: _openingHours,
            color: success,
          ),
        ],
      ),
    );
  }

  Widget _buildContactPanel() {
    return _buildPanel(
      title: 'Contact Details',
      icon: Icons.contact_phone_rounded,
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Hospital phone',
            value: _phone,
            color: accent,
          ),
          _buildInfoRow(
            icon: Icons.emergency_rounded,
            label: 'Emergency phone',
            value: _emergencyPhone,
            color: error,
          ),
          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Hospital email',
            value: _email,
            color: success,
          ),
          _buildInfoRow(
            icon: Icons.language_rounded,
            label: 'Website',
            value: _website,
            color: primary,
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatesPanel() {
    return _buildPanel(
      title: 'Map Coordinates',
      icon: Icons.map_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _hasCoordinates
                  ? accent.withValues(alpha: 0.07)
                  : warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hasCoordinates
                    ? accent.withValues(alpha: 0.20)
                    : warning.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _hasCoordinates
                      ? Icons.my_location_rounded
                      : Icons.location_off_rounded,
                  color: _hasCoordinates ? accent : warning,
                  size: 34,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _hasCoordinates
                        ? 'Coordinates are linked to this hospital record. These can later be used by the patient app for directions and nearby-hospital features.'
                        : 'No coordinates have been saved yet. Add latitude and longitude through Manage Location.',
                    style: TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CoordinateBox(
                  label: 'Latitude',
                  value: _latitude,
                  icon: Icons.north_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _CoordinateBox(
                  label: 'Longitude',
                  value: _longitude,
                  icon: Icons.east_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cBgSecondary,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

class _LocationStatusCard {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _LocationStatusCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _CoordinateBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CoordinateBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.cBgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CorviaColors.accent),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: CorviaColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: CorviaColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
