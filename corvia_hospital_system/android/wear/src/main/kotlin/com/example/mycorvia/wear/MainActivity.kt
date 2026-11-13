package com.example.mycorvia.wear

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import android.widget.TextView

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : Activity() {
    private lateinit var store: CorviaWearStore

    private lateinit var preferences:
            SharedPreferences

    private val preferenceListener =
        SharedPreferences
            .OnSharedPreferenceChangeListener {
                    _,
                    _,
                ->
                render()
            }

    override fun onCreate(
        savedInstanceState: Bundle?,
    ) {
        super.onCreate(savedInstanceState)

        store = CorviaWearStore(this)

        preferences =
            getSharedPreferences(
                CorviaWearStore.PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )

        window.statusBarColor = Color.BLACK

        render()
    }

    override fun onResume() {
        super.onResume()

        preferences
            .registerOnSharedPreferenceChangeListener(
                preferenceListener,
            )

        render()
    }

    override fun onPause() {
        preferences
            .unregisterOnSharedPreferenceChangeListener(
                preferenceListener,
            )

        super.onPause()
    }

    private fun render() {
        val snapshot = store.load()

        val scrollView =
            ScrollView(this).apply {
                isFillViewport = true
                setBackgroundColor(Color.BLACK)
            }

        val content =
            LinearLayout(this).apply {
                orientation =
                    LinearLayout.VERTICAL

                gravity =
                    Gravity.CENTER_HORIZONTAL

                setPadding(
                    dp(20),
                    dp(22),
                    dp(20),
                    dp(28),
                )
            }

        content.addView(
            titleText("CORVIA"),
        )

        content.addView(
            subtitleText(
                snapshot.profileLabel,
            ),
        )

        content.addView(
            verticalSpace(14),
        )

        val heartRateText =
            if (
                snapshot.heartRateBpm > 0
            ) {
                "${snapshot.heartRateBpm.toInt()} bpm"
            } else {
                "-- bpm"
            }

        content.addView(
            section(
                heading = "Heart Rate",
                value = heartRateText,
                detail = formatTime(
                    snapshot
                        .heartRateRecordedAtEpochMs,
                    emptyValue =
                        "No watch measurement yet",
                ),
            ),
        )

        val medicationName =
            when {
                !snapshot.sensitiveDetailsVisible ->
                    "Hidden on watch"

                snapshot
                    .nextMedicationName
                    .isBlank() ->
                    "No reminder"

                else ->
                    snapshot.nextMedicationName
            }

        content.addView(
            section(
                heading = "Next Medication",
                value = medicationName,
                detail = formatTime(
                    snapshot
                        .nextMedicationAtEpochMs,
                    emptyValue =
                        "No medication time",
                ),
            ),
        )

        val appointmentTitle =
            when {
                !snapshot.sensitiveDetailsVisible ->
                    "Hidden on watch"

                snapshot
                    .nextAppointmentTitle
                    .isBlank() ->
                    "No upcoming appointment"

                else ->
                    snapshot.nextAppointmentTitle
            }

        content.addView(
            section(
                heading = "Next Appointment",
                value = appointmentTitle,
                detail = formatTime(
                    snapshot
                        .nextAppointmentAtEpochMs,
                    emptyValue =
                        "No appointment time",
                ),
            ),
        )

        val pharmacyStatus =
            if (
                snapshot.pharmacyStatus.isBlank()
            ) {
                "No pharmacy update"
            } else {
                prettyStatus(
                    snapshot.pharmacyStatus,
                )
            }

        val pharmacyReference =
            when {
                !snapshot.sensitiveDetailsVisible ->
                    "Reference hidden"

                snapshot
                    .collectionReference
                    .isBlank() ->
                    "No collection reference"

                else ->
                    snapshot.collectionReference
            }

        content.addView(
            section(
                heading = "Pharmacy",
                value = pharmacyStatus,
                detail = pharmacyReference,
            ),
        )

        content.addView(
            section(
                heading = "Notifications",
                value =
                    snapshot
                        .unreadNotifications
                        .coerceAtLeast(0)
                        .toString(),
                detail = "Unread Corvia alerts",
            ),
        )

        content.addView(
            section(
                heading = "Emergency Profile",
                value =
                    if (
                        snapshot
                            .emergencyProfileAvailable
                    ) {
                        "Available"
                    } else {
                        "Not available"
                    },
                detail =
                    "Open the phone app for full emergency details",
            ),
        )

        content.addView(
            verticalSpace(12),
        )

        content.addView(
            smallText(
                "Last sync: ${
                    formatTime(
                        snapshot.syncedAtEpochMs,
                        "Not synced",
                    )
                }",
            ),
        )

        scrollView.addView(content)

        setContentView(scrollView)
    }

    private fun titleText(
        value: String,
    ): TextView {
        return TextView(this).apply {
            text = value
            textSize = 22f
            setTextColor(
                Color.rgb(
                    0,
                    180,
                    216,
                ),
            )
            typeface =
                Typeface.DEFAULT_BOLD
            gravity =
                Gravity.CENTER
        }
    }

    private fun subtitleText(
        value: String,
    ): TextView {
        return TextView(this).apply {
            text = value
            textSize = 13f
            setTextColor(
                Color.LTGRAY,
            )
            gravity =
                Gravity.CENTER
        }
    }

    private fun smallText(
        value: String,
    ): TextView {
        return TextView(this).apply {
            text = value
            textSize = 10f
            setTextColor(
                Color.GRAY,
            )
            gravity =
                Gravity.CENTER
        }
    }

    private fun section(
        heading: String,
        value: String,
        detail: String,
    ): View {
        val container =
            LinearLayout(this).apply {
                orientation =
                    LinearLayout.VERTICAL

                setPadding(
                    dp(14),
                    dp(12),
                    dp(14),
                    dp(12),
                )

                background =
                    GradientDrawable().apply {
                        cornerRadius =
                            dp(14).toFloat()

                        setColor(
                            Color.rgb(
                                21,
                                35,
                                48,
                            ),
                        )

                        setStroke(
                            dp(1),
                            Color.rgb(
                                42,
                                67,
                                82,
                            ),
                        )
                    }
            }

        val layoutParams =
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                bottomMargin = dp(10)
            }

        container.layoutParams = layoutParams

        container.addView(
            TextView(this).apply {
                text = heading
                textSize = 11f

                setTextColor(
                    Color.rgb(
                        0,
                        180,
                        216,
                    ),
                )

                typeface =
                    Typeface.DEFAULT_BOLD
            },
        )

        container.addView(
            TextView(this).apply {
                text = value
                textSize = 17f
                setTextColor(Color.WHITE)

                typeface =
                    Typeface.DEFAULT_BOLD

                setPadding(
                    0,
                    dp(3),
                    0,
                    0,
                )
            },
        )

        container.addView(
            TextView(this).apply {
                text = detail
                textSize = 10f

                setTextColor(
                    Color.LTGRAY,
                )

                setPadding(
                    0,
                    dp(4),
                    0,
                    0,
                )
            },
        )

        return container
    }

    private fun verticalSpace(
        heightDp: Int,
    ): View {
        return Space(this).apply {
            layoutParams =
                LinearLayout.LayoutParams(
                    1,
                    dp(heightDp),
                )
        }
    }

    private fun formatTime(
        epochMs: Long,
        emptyValue: String,
    ): String {
        if (epochMs <= 0) {
            return emptyValue
        }

        return try {
            SimpleDateFormat(
                "dd MMM • HH:mm",
                Locale.getDefault(),
            ).format(
                Date(epochMs),
            )
        } catch (_: Exception) {
            emptyValue
        }
    }

    private fun prettyStatus(
        status: String,
    ): String {
        return status
            .trim()
            .replace("-", "_")
            .split("_")
            .filter {
                it.isNotBlank()
            }
            .joinToString(" ") {
                    word ->
                word.lowercase()
                    .replaceFirstChar {
                            character ->
                        character.uppercase()
                    }
            }
    }

    private fun dp(
        value: Int,
    ): Int {
        return (
                value *
                        resources
                            .displayMetrics
                            .density
                ).toInt()
    }
}