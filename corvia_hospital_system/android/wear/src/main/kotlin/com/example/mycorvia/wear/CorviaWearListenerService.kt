package com.example.mycorvia.wear

import android.util.Log

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

class CorviaWearListenerService :
    WearableListenerService() {

    companion object {
        private const val TAG =
            "CorviaWearListener"

        private const val CORVIA_STATUS_PATH =
            "/corvia/status"
    }

    override fun onDataChanged(
        dataEvents: DataEventBuffer,
    ) {
        super.onDataChanged(dataEvents)

        for (event in dataEvents) {
            if (
                event.type !=
                DataEvent.TYPE_CHANGED
            ) {
                continue
            }

            val dataItem = event.dataItem

            if (
                dataItem.uri.path !=
                CORVIA_STATUS_PATH
            ) {
                continue
            }

            try {
                val dataMap =
                    DataMapItem
                        .fromDataItem(dataItem)
                        .dataMap

                CorviaWearStore(this)
                    .save(dataMap)

                Log.d(
                    TAG,
                    "Corvia wearable snapshot updated.",
                )
            } catch (error: Exception) {
                Log.e(
                    TAG,
                    "Could not process Corvia wearable snapshot.",
                    error,
                )
            }
        }
    }
}