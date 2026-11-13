
import 'dispatch_history_report_panel.dart';

/// Validates records supplied by an authorised dispatch history service.
///
/// Does not query Supabase or infer completion from a status string.
/// A complete reporting scope must be explicitly confirmed by the backend.
class DispatchReportIntegrity {
  DispatchReportIntegrity._({
    required this.safeRecords,
    required this.duplicateIncidentIds,
    required this.invalidIdentityCount,
    required this.unverifiedCompletionCount,
    required this.missingOutcomeCount,
    required this.missingTimingCount,
    required this.invalidTimingCount,
    required this.originalRecordCount,
    required this.serverConfirmedComplete,
  });

  final List<DispatchHistoryRecord> safeRecords;
  final List<String> duplicateIncidentIds;

  final int invalidIdentityCount;
  final int unverifiedCompletionCount;
  final int missingOutcomeCount;
  final int missingTimingCount;
  final int invalidTimingCount;
  final int originalRecordCount;

  final bool serverConfirmedComplete;

  static DispatchReportIntegrity inspect(
    List<DispatchHistoryRecord> records, {
    bool serverConfirmedComplete = false,
  }) {
    final frequencies = <String, int>{};
    var invalidIdentities = 0;

    for (final record in records) {
      final id = record.incidentId.trim().toLowerCase();

      if (id.isEmpty) {
        invalidIdentities++;
        continue;
      }

      frequencies.update(
        id,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final duplicateIds = frequencies.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList()
      ..sort();

    final duplicateSet = duplicateIds.toSet();

    // Exclude all ambiguous duplicate IDs rather than
    // choosing one potentially incorrect incident state.
    final accepted = records.where((record) {
      final id = record.incidentId.trim().toLowerCase();

      return id.isNotEmpty && !duplicateSet.contains(id);
    }).toList(growable: false);

    var unknownCompletions = 0;
    var missingOutcomes = 0;
    var missingTimings = 0;
    var invalidTimings = 0;

    for (final record in accepted) {
      if (record.completion ==
          DispatchCompletionState.unknown) {
        unknownCompletions++;
      }

      if (record.completion !=
          DispatchCompletionState.completed) {
        continue;
      }

      if (record.outcome == null ||
          record.outcome!.trim().isEmpty) {
        missingOutcomes++;
      }

      if (record.createdAt == null ||
          record.completedAt == null) {
        missingTimings++;
        continue;
      }

      if (record.completedAt!.isBefore(record.createdAt!)) {
        invalidTimings++;
      }
    }

    return DispatchReportIntegrity._(
      safeRecords: List.unmodifiable(accepted),
      duplicateIncidentIds: List.unmodifiable(duplicateIds),
      invalidIdentityCount: invalidIdentities,
      unverifiedCompletionCount: unknownCompletions,
      missingOutcomeCount: missingOutcomes,
      missingTimingCount: missingTimings,
      invalidTimingCount: invalidTimings,
      originalRecordCount: records.length,
      serverConfirmedComplete: serverConfirmedComplete,
    );
  }

  int get countedRecordCount => safeRecords.length;

  int get confirmedCompletedCount =>
      safeRecords.where((record) {
        return record.completion ==
            DispatchCompletionState.completed;
      }).length;

  int get confirmedNotCompletedCount =>
      safeRecords.where((record) {
        return record.completion ==
            DispatchCompletionState.notCompleted;
      }).length;

  int get unknownCompletionCount =>
      unverifiedCompletionCount;

  int get excludedRecordCount =>
      originalRecordCount - countedRecordCount;

  bool get hasIdentityProblems =>
      invalidIdentityCount > 0 ||
      duplicateIncidentIds.isNotEmpty;

  bool get hasReportingGaps =>
      hasIdentityProblems ||
      unverifiedCompletionCount > 0 ||
      missingOutcomeCount > 0 ||
      missingTimingCount > 0 ||
      invalidTimingCount > 0;

  /// This only means the supplied scope was explicitly verified
  /// complete and every counted record has a unique usable ID.
  /// It does not independently prove the caller's backend authority.
  bool get canPublishScopedCounts =>
      serverConfirmedComplete && !hasIdentityProblems;

  int get validTimingCount =>
      safeRecords.where((record) {
        return record.caseElapsed != null;
      }).length;

  /// Created-to-completed case duration, not EMS response time.
  /// Missing and invalid timestamp pairs are excluded.
  Duration? get averageCaseElapsed {
    final durations = safeRecords
        .map((record) => record.caseElapsed)
        .whereType<Duration>()
        .toList();

    if (durations.isEmpty) return null;

    final totalSeconds = durations.fold<int>(
      0,
      (total, duration) => total + duration.inSeconds,
    );

    return Duration(
      seconds: (totalSeconds / durations.length).round(),
    );
  }

  /// Human-readable validation messages for an operational report.
  List<String> get findings {
    final messages = <String>[];

    if (!serverConfirmedComplete) {
      messages.add(
        'Historical scope is not confirmed complete. '
        'Counts apply only to loaded records.',
      );
    }

    if (invalidIdentityCount > 0) {
      messages.add(
        '$invalidIdentityCount record(s) have missing incident IDs '
        'and were excluded from safe counts.',
      );
    }

    if (duplicateIncidentIds.isNotEmpty) {
      messages.add(
        '${duplicateIncidentIds.length} duplicated incident ID(s) '
        'were excluded from safe counts.',
      );
    }

    if (unverifiedCompletionCount > 0) {
      messages.add(
        '$unverifiedCompletionCount incident(s) have '
        'unverified completion states.',
      );
    }

    if (missingOutcomeCount > 0) {
      messages.add(
        '$missingOutcomeCount completed incident(s) '
        'have no recorded outcome.',
      );
    }

    if (missingTimingCount > 0) {
      messages.add(
        '$missingTimingCount completed incident(s) '
        'lack a complete timestamp pair.',
      );
    }

    if (invalidTimingCount > 0) {
      messages.add(
        '$invalidTimingCount completed incident(s) '
        'have reversed timestamps.',
      );
    }

    if (messages.isEmpty) {
      messages.add(
        'No reporting integrity gaps found in the '
        'supplied records.',
      );
    }

    return List.unmodifiable(messages);
  }
}
