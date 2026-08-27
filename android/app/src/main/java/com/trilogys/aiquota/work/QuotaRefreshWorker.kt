package com.trilogys.aiquota.work

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.trilogys.aiquota.core.AccountStore
import com.trilogys.aiquota.core.CredentialStore
import com.trilogys.aiquota.core.QuotaNotifier
import com.trilogys.aiquota.core.UsageService
import com.trilogys.aiquota.widget.AIQuotaWidget
import com.trilogys.aiquota.widget.WidgetConfigStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class QuotaRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val accountStore = AccountStore(applicationContext)
        val usageService = UsageService(CredentialStore(applicationContext))
        val notifier = QuotaNotifier(applicationContext)
        val appWidgetId = inputData.getInt(KEY_APP_WIDGET_ID, -1)
        val config = if (appWidgetId >= 0) WidgetConfigStore(applicationContext).get(appWidgetId) else null
        val enabledAccounts = accountStore.accounts().filter { it.enabled }
        val targets = enabledAccounts.filter { account ->
            when (config?.mode) {
                WidgetConfigStore.Mode.PROVIDER -> account.provider == config.provider
                WidgetConfigStore.Mode.ACCOUNT -> account.id == config.accountId
                WidgetConfigStore.Mode.ALL, null -> true
            }
        }

        var hadSuccess = false
        targets.forEach { account ->
            runCatching { usageService.refresh(account) }
                .onSuccess {
                    accountStore.saveSnapshot(it)
                    notifier.evaluate(account, it)
                    hadSuccess = true
                }
                .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
        }
        AIQuotaWidget().updateAll(applicationContext)
        if (hadSuccess || targets.isEmpty()) Result.success() else Result.retry()
    }

    companion object {
        const val KEY_APP_WIDGET_ID = "app_widget_id"
    }
}
