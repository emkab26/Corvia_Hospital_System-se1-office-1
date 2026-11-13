package com.example.mycorvia.wear

import android.content.Context
import android.content.SharedPreferences

import com.google.android.gms.wearable.DataMap

class CorviaWearStore(
    context: Context,
) {
    companion object {
        const val PREFERENCES_NAME =
            "corvia_wear_snapshot"

        private const val KEY_SNAPSHOT_VERSION =
            "snapshotVersion"

        private const val KEY_PROFILE_LABEL =
            "profileLabel"

        private const val KEY_HEART_RATE =
            "heartRateBpm"

        private const val KEY_HEART_RATE_TIME =
            "heartRateRecordedAtEpochMs"

        private const val KEY_MEDICATION_NAME =
            "nextMedicationName"

        private const val KEY_MEDICATION_TIME =
            "nextMedicationAtEpochMs"

        private const val KEY_APPOINTMENT_TITLE =
            "nextAppointmentTitle"

        private const val KEY_APPOINTMENT_TIME =
            "nextAppointmentAtEpochMs"

        private const val KEY_PHARMACY_STATUS =
            "pharmacyStatus"

        private const val KEY_COLLECTION_REFERENCE =
            "collectionReference"

        private const val KEY_UNREAD_NOTIFICATIONS =
            "unreadNotifications"

        private const val KEY_EMERGENCY_AVAILABLE =
            "emergencyProfileAvailable"

        private const val KEY_SENSITIVE_VISIBLE =
            "sensitiveDetailsVisible"

        private const val KEY_SYNCED_AT =
            "syncedAtEpochMs"
    }

    private val preferences: SharedPreferences =
        context.getSharedPreferences(
            PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )

    fun save(
        dataMap: DataMap,
    ) {
        preferences
            .edit()
            .putLong(
                KEY_SNAPSHOT_VERSION,
                dataMap.getLong(
                    KEY_SNAPSHOT_VERSION,
                    1L,
                ),
            )
            .putString(
                KEY_PROFILE_LABEL,
                dataMap.getString(
                    KEY_PROFILE_LABEL,
                    "Corvia Patient",
                ),
            )
            .putString(
                KEY_HEART_RATE,
                dataMap.getDouble(
                    KEY_HEART_RATE,
                    -1.0,
                ).toString(),
            )
            .putLong(
                KEY_HEART_RATE_TIME,
                dataMap.getLong(
                    KEY_HEART_RATE_TIME,
                    0L,
                ),
            )
            .putString(
                KEY_MEDICATION_NAME,
                dataMap.getString(
                    KEY_MEDICATION_NAME,
                    "",
                ),
            )
            .putLong(
                KEY_MEDICATION_TIME,
                dataMap.getLong(
                    KEY_MEDICATION_TIME,
                    0L,
                ),
            )
            .putString(
                KEY_APPOINTMENT_TITLE,
                dataMap.getString(
                    KEY_APPOINTMENT_TITLE,
                    "",
                ),
            )
            .putLong(
                KEY_APPOINTMENT_TIME,
                dataMap.getLong(
                    KEY_APPOINTMENT_TIME,
                    0L,
                ),
            )
            .putString(
                KEY_PHARMACY_STATUS,
                dataMap.getString(
                    KEY_PHARMACY_STATUS,
                    "",
                ),
            )
            .putString(
                KEY_COLLECTION_REFERENCE,
                dataMap.getString(
                    KEY_COLLECTION_REFERENCE,
                    "",
                ),
            )
            .putInt(
                KEY_UNREAD_NOTIFICATIONS,
                dataMap.getInt(
                    KEY_UNREAD_NOTIFICATIONS,
                    0,
                ),
            )
            .putBoolean(
                KEY_EMERGENCY_AVAILABLE,
                dataMap.getBoolean(
                    KEY_EMERGENCY_AVAILABLE,
                    false,
                ),
            )
            .putBoolean(
                KEY_SENSITIVE_VISIBLE,
                dataMap.getBoolean(
                    KEY_SENSITIVE_VISIBLE,
                    false,
                ),
            )
            .putLong(
                KEY_SYNCED_AT,
                dataMap.getLong(
                    KEY_SYNCED_AT,
                    System.currentTimeMillis(),
                ),
            )
            .apply()
    }

    fun load(): CorviaWearSnapshot {
        return CorviaWearSnapshot(
            snapshotVersion =
                preferences.getLong(
                    KEY_SNAPSHOT_VERSION,
                    1L,
                ),
            profileLabel =
                preferences.getString(
                    KEY_PROFILE_LABEL,
                    "Corvia Patient",
                ) ?: "Corvia Patient",
            heartRateBpm =
                preferences.getString(
                    KEY_HEART_RATE,
                    "-1.0",
                )?.toDoubleOrNull() ?: -1.0,
            heartRateRecordedAtEpochMs =
                preferences.getLong(
                    KEY_HEART_RATE_TIME,
                    0L,
                ),
            nextMedicationName =
                preferences.getString(
                    KEY_MEDICATION_NAME,
                    "",
                ) ?: "",
            nextMedicationAtEpochMs =
                preferences.getLong(
                    KEY_MEDICATION_TIME,
                    0L,
                ),
            nextAppointmentTitle =
                preferences.getString(
                    KEY_APPOINTMENT_TITLE,
                    "",
                ) ?: "",
            nextAppointmentAtEpochMs =
                preferences.getLong(
                    KEY_APPOINTMENT_TIME,
                    0L,
                ),
            pharmacyStatus =
                preferences.getString(
                    KEY_PHARMACY_STATUS,
                    "",
                ) ?: "",
            collectionReference =
                preferences.getString(
                    KEY_COLLECTION_REFERENCE,
                    "",
                ) ?: "",
            unreadNotifications =
                preferences.getInt(
                    KEY_UNREAD_NOTIFICATIONS,
                    0,
                ),
            emergencyProfileAvailable =
                preferences.getBoolean(
                    KEY_EMERGENCY_AVAILABLE,
                    false,
                ),
            sensitiveDetailsVisible =
                preferences.getBoolean(
                    KEY_SENSITIVE_VISIBLE,
                    false,
                ),
            syncedAtEpochMs =
                preferences.getLong(
                    KEY_SYNCED_AT,
                    0L,
                ),
        )
    }
}

data class CorviaWearSnapshot(
    val snapshotVersion: Long,
    val profileLabel: String,
    val heartRateBpm: Double,
    val heartRateRecordedAtEpochMs: Long,
    val nextMedicationName: String,
    val nextMedicationAtEpochMs: Long,
    val nextAppointmentTitle: String,
    val nextAppointmentAtEpochMs: Long,
    val pharmacyStatus: String,
    val collectionReference: String,
    val unreadNotifications: Int,
    val emergencyProfileAvailable: Boolean,
    val sensitiveDetailsVisible: Boolean,
    val syncedAtEpochMs: Long,
)