package com.example.mycorvia

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager

import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val HAPTIC_CHANNEL =
            "com.example.mycorvia/haptic"

        private const val WEARABLE_CHANNEL =
            "com.example.mycorvia/wearable"

        private const val WEARABLE_DATA_PATH =
            "/corvia/status"
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        configureHapticChannel(flutterEngine)
        configureWearableChannel(flutterEngine)
    }

    private fun configureHapticChannel(
        flutterEngine: FlutterEngine,
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HAPTIC_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isHapticSupported" -> {
                    result.success(
                        isHapticSupported(),
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun configureWearableChannel(
        flutterEngine: FlutterEngine,
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WEARABLE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getConnectedWatchCount" -> {
                    getConnectedWatchCount(result)
                }

                "syncSnapshot" -> {
                    val arguments =
                        call.arguments as? Map<*, *>

                    if (arguments == null) {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "Wearable snapshot data is missing.",
                            null,
                        )

                        return@setMethodCallHandler
                    }

                    syncSnapshot(
                        arguments = arguments,
                        result = result,
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getConnectedWatchCount(
        result: MethodChannel.Result,
    ) {
        try {
            Wearable
                .getNodeClient(this)
                .connectedNodes
                .addOnSuccessListener { nodes ->
                    result.success(nodes.size)
                }
                .addOnFailureListener { error ->
                    result.error(
                        "WATCH_CONNECTION_FAILED",
                        error.message
                            ?: "Could not check connected watches.",
                        null,
                    )
                }
        } catch (error: Exception) {
            result.error(
                "WEARABLE_API_UNAVAILABLE",
                error.message
                    ?: "Wear OS services are unavailable.",
                null,
            )
        }
    }

    private fun syncSnapshot(
        arguments: Map<*, *>,
        result: MethodChannel.Result,
    ) {
        try {
            val request =
                PutDataMapRequest.create(
                    WEARABLE_DATA_PATH,
                ).apply {
                    dataMap.putLong(
                        "snapshotVersion",
                        longArgument(
                            arguments,
                            "snapshotVersion",
                            1L,
                        ),
                    )

                    dataMap.putString(
                        "profileLabel",
                        stringArgument(
                            arguments,
                            "profileLabel",
                            "Corvia Patient",
                        ),
                    )

                    dataMap.putDouble(
                        "heartRateBpm",
                        doubleArgument(
                            arguments,
                            "heartRateBpm",
                            -1.0,
                        ),
                    )

                    dataMap.putLong(
                        "heartRateRecordedAtEpochMs",
                        longArgument(
                            arguments,
                            "heartRateRecordedAtEpochMs",
                            0L,
                        ),
                    )

                    dataMap.putString(
                        "nextMedicationName",
                        stringArgument(
                            arguments,
                            "nextMedicationName",
                            "",
                        ),
                    )

                    dataMap.putLong(
                        "nextMedicationAtEpochMs",
                        longArgument(
                            arguments,
                            "nextMedicationAtEpochMs",
                            0L,
                        ),
                    )

                    dataMap.putString(
                        "nextAppointmentTitle",
                        stringArgument(
                            arguments,
                            "nextAppointmentTitle",
                            "",
                        ),
                    )

                    dataMap.putLong(
                        "nextAppointmentAtEpochMs",
                        longArgument(
                            arguments,
                            "nextAppointmentAtEpochMs",
                            0L,
                        ),
                    )

                    dataMap.putString(
                        "pharmacyStatus",
                        stringArgument(
                            arguments,
                            "pharmacyStatus",
                            "",
                        ),
                    )

                    dataMap.putString(
                        "collectionReference",
                        stringArgument(
                            arguments,
                            "collectionReference",
                            "",
                        ),
                    )

                    dataMap.putInt(
                        "unreadNotifications",
                        intArgument(
                            arguments,
                            "unreadNotifications",
                            0,
                        ),
                    )

                    dataMap.putBoolean(
                        "emergencyProfileAvailable",
                        booleanArgument(
                            arguments,
                            "emergencyProfileAvailable",
                            false,
                        ),
                    )

                    dataMap.putBoolean(
                        "sensitiveDetailsVisible",
                        booleanArgument(
                            arguments,
                            "sensitiveDetailsVisible",
                            false,
                        ),
                    )

                    dataMap.putLong(
                        "syncedAtEpochMs",
                        longArgument(
                            arguments,
                            "syncedAtEpochMs",
                            System.currentTimeMillis(),
                        ),
                    )
                }
                    .asPutDataRequest()
                    .setUrgent()

            Wearable
                .getDataClient(this)
                .putDataItem(request)
                .addOnSuccessListener { dataItem ->
                    result.success(
                        mapOf(
                            "success" to true,
                            "path" to (
                                    dataItem.uri.path
                                        ?: WEARABLE_DATA_PATH
                                    ),
                            "uri" to dataItem.uri.toString(),
                        ),
                    )
                }
                .addOnFailureListener { error ->
                    result.error(
                        "WEARABLE_SYNC_FAILED",
                        error.message
                            ?: "Could not sync Corvia data to the watch.",
                        null,
                    )
                }
        } catch (error: Exception) {
            result.error(
                "WEARABLE_SYNC_FAILED",
                error.message
                    ?: "Could not sync Corvia data to the watch.",
                null,
            )
        }
    }

    private fun stringArgument(
        arguments: Map<*, *>,
        key: String,
        fallback: String,
    ): String {
        val value =
            arguments[key]?.toString()?.trim()

        return if (value.isNullOrEmpty()) {
            fallback
        } else {
            value
        }
    }

    private fun longArgument(
        arguments: Map<*, *>,
        key: String,
        fallback: Long,
    ): Long {
        val value = arguments[key]

        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun intArgument(
        arguments: Map<*, *>,
        key: String,
        fallback: Int,
    ): Int {
        val value = arguments[key]

        return when (value) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun doubleArgument(
        arguments: Map<*, *>,
        key: String,
        fallback: Double,
    ): Double {
        val value = arguments[key]

        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun booleanArgument(
        arguments: Map<*, *>,
        key: String,
        fallback: Boolean,
    ): Boolean {
        val value = arguments[key]

        return when (value) {
            is Boolean -> value

            is String -> {
                when (value.trim().lowercase()) {
                    "true",
                    "1",
                    "yes",
                        -> true

                    "false",
                    "0",
                    "no",
                        -> false

                    else -> fallback
                }
            }

            is Number -> value.toInt() != 0

            else -> fallback
        }
    }

    private fun isHapticSupported(): Boolean {
        return if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.S
        ) {
            val vibratorManager =
                getSystemService(
                    Context.VIBRATOR_MANAGER_SERVICE,
                ) as? VibratorManager

            vibratorManager
                ?.defaultVibrator
                ?.hasVibrator()
                ?: false
        } else {
            @Suppress("DEPRECATION")
            val vibrator =
                getSystemService(
                    Context.VIBRATOR_SERVICE,
                ) as? Vibrator

            vibrator?.hasVibrator() ?: false
        }
    }
}