package com.trilogys.aiquota.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.AppWidgetId
import androidx.glance.appwidget.action.ActionCallback
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.trilogys.aiquota.work.QuotaRefreshWorker

class RefreshWidgetAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val appWidgetId = (glanceId as? AppWidgetId)?.appWidgetId
        val request = OneTimeWorkRequestBuilder<QuotaRefreshWorker>()
            .setInputData(workDataOf(QuotaRefreshWorker.KEY_APP_WIDGET_ID to (appWidgetId ?: -1)))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "aiquota-widget-refresh-${appWidgetId ?: "all"}",
            ExistingWorkPolicy.REPLACE,
            request
        )
    }
}
