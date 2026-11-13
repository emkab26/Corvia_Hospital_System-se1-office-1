import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../services/doctor_directory.dart';
import '../../services/doctor_favourites_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_view.dart';
import 'book_appointment.dart';
import 'chat_with_doctor.dart';
import 'doctor_detail.dart';

class FindADoctorPage extends StatefulWidget {
  const FindADoctorPage({super.key});

  @override
  State<FindADoctorPage> createState() => _FindADoctorPageState();
}

class _FindADoctorPageState extends State<FindADoctorPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  Future<List<DoctorEntry>>? _future;
  String _query = '';
  bool _hasUserLocation = false;
  String _selectedSpecialty = 'All';
  Set<String> _favouriteIds = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadFavourites();

    _searchCtrl.addListener(() {
      setState(() {
        _query = _searchCtrl.text;
      });
    });
  }

  Future<void> _loadFavourites() async {
    try {
      final ids = await DoctorFavouritesService.fetchFavouriteIds();
      if (mounted) setState(() => _favouriteIds = ids);
    } catch (e) {
      // Degrades gracefully if the doctor_favourites table isn't present yet.
      debugPrint('FindADoctor: failed to load favourites: $e');
    }
  }

  Future<void> _toggleFavourite(String doctorId) async {
    final wasFav = _favouriteIds.contains(doctorId);
    setState(() {
      _favouriteIds = Set.from(_favouriteIds);
      if (wasFav) {
        _favouriteIds.remove(doctorId);
      } else {
        _favouriteIds.add(doctorId);
      }
    });
    try {
      await DoctorFavouritesService.toggleFavourite(
        doctorId,
        isFavourite: !wasFav,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _favouriteIds = Set.from(_favouriteIds);
        if (wasFav) {
          _favouriteIds.add(doctorId);
        } else {
          _favouriteIds.remove(doctorId);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _loadAll();
    });
  }

  Future<List<DoctorEntry>> _loadAll() async {
    _hasUserLocation = await DoctorDirectory.userLocationAvailable();
    return DoctorDirectory.load(requireAvailable: false);
  }

  List<DoctorEntry> _filter(List<DoctorEntry> all) {
    var filteredList = all;

    // Filter by category chip selection first
    if (_selectedSpecialty != 'All') {
      filteredList = filteredList
          .where(
            (doctor) => _matchesSpecialty(
              doctor.specialization,
              _selectedSpecialty,
            ),
          )
          .toList();
    }

    filteredList = DoctorFavouritesService.favouritesFirst(
      filteredList,
      _favouriteIds,
      (doctor) => doctor.doctorId,
    );

    final cleanQuery = _query.trim().toLowerCase();

    if (cleanQuery.isEmpty) return filteredList;

    return filteredList.where((doctor) {
      final name = '${doctor.firstName} ${doctor.surname}'.toLowerCase();
      final displayName = doctor.displayName.toLowerCase();
      final specialization = doctor.specialization.toLowerCase();
      final location = doctor.location.toLowerCase();

      return name.contains(cleanQuery) ||
          displayName.contains(cleanQuery) ||
          specialization.contains(cleanQuery) ||
          location.contains(cleanQuery);
    }).toList();
  }

  /// Doctors record specialties in free text ("General Practice",
  /// "Cardiologist", "Paediatrics"), so match on a shared word stem rather
  /// than exact equality with the chip label.
  static bool _matchesSpecialty(String specialization, String chip) {
    final spec = specialization.trim().toLowerCase();
    final selected = chip.trim().toLowerCase();

    if (selected == 'general practitioner') {
      return spec.isEmpty ||
          spec == 'gp' ||
          spec.startsWith('general pract') ||
          spec.contains('family');
    }

    // British/American spellings: Paediatrics/Pediatrics, Gynaecology.
    final normalisedSpec = spec.replaceAll('ae', 'e');
    final normalisedChip = selected.replaceAll('ae', 'e');
    final root = normalisedChip.length > 6
        ? normalisedChip.substring(0, 6)
        : normalisedChip;
    return normalisedSpec.contains(root);
  }

  Future<void> _refreshAsync() async {
    _refresh();
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cBgPrimary,
      appBar: AppBar(
        title: const Text('Find a Doctor'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: CorviaColors.accent,
              decoration: InputDecoration(
                hintText: 'Search by name, specialty, or city',
                hintStyle: TextStyle(color: context.cTextMuted),
                labelStyle: TextStyle(color: context.cTextSecondary),
                filled: true,
                fillColor: context.cBgSecondary,
                prefixIcon: Icon(
                  Icons.search,
                  color: CorviaColors.accentLight,
                ),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: context.cTextMuted,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: AppConstants.medicalSpecialties.length,
              itemBuilder: (context, index) {
                final specialty = AppConstants.medicalSpecialties[index];
                final isSelected = _selectedSpecialty == specialty;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(specialty),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : context.cTextPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    selectedColor: const Color(
                        0xFF2563EB), // Rich blue matching your screenshot
                    checkmarkColor: Colors.white,
                    showCheckmark: specialty == 'All',
                    backgroundColor: context.cBgSecondary,
                    elevation: 0,
                    pressElevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    onSelected: (bool selected) {
                      setState(() {
                        _selectedSpecialty = specialty;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_hasUserLocation)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.my_location,
                    size: 14,
                    color: CorviaColors.accentLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Sorted by distance from you',
                    style: TextStyle(
                      color: context.cTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAsync,
              child: FutureBuilder<List<DoctorEntry>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return StatusView.loading(message: 'Finding doctors...');
                  }

                  if (snap.hasError) {
                    return StatusView.error(
                      friendlyMessage: 'Could not load the doctor directory.',
                      error: snap.error,
                      stackTrace: snap.stackTrace,
                      onRetry: _refresh,
                    );
                  }

                  final allDoctors = snap.data ?? const [];
                  final results = _filter(allDoctors);

                  if (allDoctors.isEmpty) {
                    return StatusView.empty(
                      icon: Icons.medical_services_outlined,
                      title: 'No doctors registered yet',
                      subtitle:
                          'Once a doctor is added by an administrator, they will appear here.',
                      onRetry: _refresh,
                    );
                  }

                  if (results.isEmpty) {
                    return StatusView.empty(
                      icon: Icons.search_off,
                      title: 'No doctors match your search',
                      subtitle: 'Try a different name, specialty, or city.',
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final doctor = results[index];

                      return _DoctorCard(
                        doctor: doctor,
                        isFavourite: _favouriteIds.contains(doctor.doctorId),
                        onToggleFavourite: () =>
                            _toggleFavourite(doctor.doctorId),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoctorDetailPage(doctor: doctor),
                            ),
                          );
                        },
                        onChat: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChatWithDoctorPage(),
                            ),
                          );
                        },
                        onBook: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BookingApp(),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.isFavourite,
    required this.onToggleFavourite,
    required this.onTap,
    required this.onChat,
    required this.onBook,
  });

  final DoctorEntry doctor;
  final bool isFavourite;
  final VoidCallback onToggleFavourite;
  final VoidCallback onTap;
  final VoidCallback onChat;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (doctor.specialization.isNotEmpty) doctor.specialization,
      if (doctor.location.isNotEmpty) doctor.location,
      if (!doctor.available) 'Currently unavailable',
    ];

    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: context.cBgSecondary,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor:
                doctor.available ? CorviaColors.success : context.cTextMuted,
            child: const Icon(
              Icons.medical_services,
              color: Colors.white,
            ),
          ),
          title: Text(
            doctor.displayName,
            style: TextStyle(
              color: context.cTextPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lines.isNotEmpty)
                Text(
                  lines.join(' • '),
                  style: TextStyle(
                    color: context.cTextSecondary,
                  ),
                ),
              if (doctor.distanceLabel.isNotEmpty)
                Text(
                  doctor.distanceLabel,
                  style: TextStyle(
                    color: CorviaColors.accentLight,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.local_hospital_outlined,
                label: 'Practice',
                value: doctor.specialization.isNotEmpty
                    ? doctor.specialization
                    : AppConstants.defaultSpecialty,
              ),
              const SizedBox(height: 2),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: doctor.location.isNotEmpty
                    ? doctor.location
                    : 'Johannesburg',
              ),
              const SizedBox(height: 2),
              _InfoRow(
                icon: Icons.schedule_outlined,
                label: 'Availability',
                value: _availabilitySummary(context, doctor),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: isFavourite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                icon: Icon(
                  isFavourite ? Icons.favorite : Icons.favorite_border,
                  color: isFavourite ? Colors.redAccent : context.cTextMuted,
                ),
                onPressed: onToggleFavourite,
              ),
              IconButton(
                tooltip: 'Chat',
                icon: Icon(
                  Icons.chat_bubble_outline,
                  color: CorviaColors.accentLight,
                ),
                onPressed: doctor.available ? onChat : null,
              ),
              IconButton(
                key: const Key('bookDoctorButton'),
                tooltip: 'Book',
                icon: Icon(
                  Icons.calendar_today,
                  color: CorviaColors.accentLight,
                ),
                onPressed: doctor.available ? onBook : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Map<int, String> _weekdayShortNames = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

String _formatWorkingDays(List<int> workingDays) {
  if (workingDays.isEmpty) return 'Mon - Fri';

  final sortedDays = [...workingDays]..sort();

  final isContiguousRange = sortedDays.length > 1 &&
      (sortedDays.last - sortedDays.first) == (sortedDays.length - 1);

  if (isContiguousRange) {
    final startLabel = _weekdayShortNames[sortedDays.first] ?? '';
    final endLabel = _weekdayShortNames[sortedDays.last] ?? '';
    return '$startLabel - $endLabel';
  }

  return sortedDays
      .map((day) => _weekdayShortNames[day] ?? '')
      .where((label) => label.isNotEmpty)
      .join(', ');
}

String _availabilitySummary(BuildContext context, DoctorEntry doctor) {
  final daysText = _formatWorkingDays(doctor.workingDays);
  final startTime = doctor.workStart.format(context);
  final endTime = doctor.workEnd.format(context);

  return '$daysText • $startTime - $endTime';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: context.cTextMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label: $value',
            style: TextStyle(
              color: context.cTextSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
