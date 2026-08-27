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
import java.io.IOException

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
        var hadRetryableFailure = false
        targets.forEach { account ->
            runCatching { usageService.refresh(account) }
                .onSuccess {
                    accountStore.saveSnapshot(it)
                    notifier.evaluate(account, it)
                    hadSuccess = true
                }
                .onFailure { error ->
                    val failure = classifyFailure(error)
                    accountStore.markStale(account.id, failure.userMessage)
                    if (failure.retryable) hadRetryableFailure = true
                }
        }
        AIQuotaWidget().updateAll(applicationContext)

        when {
            targets.isEmpty() || hadSuccess -> Result.success()
            hadRetryableFailure && runAttemptCount < MAX_RETRY_ATTEMPTS -> Result.retry()
            else -> Result.success()
        }
    }

    private fun classifyFailure(error: Throwable): RefreshFailure {
        val raw = error.message.orEmpty()
        val lower = raw.lowercase()
        val status = HTTP_STATUS_REGEX.find(raw)?.groupValues?.getOrNull(1)?.toIntOrNull()

        return when {
            status == 401 || status == 403 -> RefreshFailure(
                retryable = false,
                userMessage = "Authentication expired. Please sign in again."
            )
            status == 429 -> RefreshFailure(
                retryable = true,
                userMessage = "Provider rate limit reached. Refresh will retry later."
            )
            status != null && status >= 500 -> RefreshFailure(
                retryable = true,
                userMessage = "Provider is temporarily unavailable (HTTP $status)."
            )
            error is IOException -> RefreshFailure(
                retryable = true,
                userMessage = "Network or provider connection failed."
            )
            lower.contains("missing credential") -> RefreshFailure(
                retryable = false,
                userMessage = "Account credentials are missing. Please sign in again."
            )
            lower.contains("json") || lower.contains("parse") || lower.contains("unexpected") -> RefreshFailure(
                retryable = false,
                userMessage = "Provider response format changed. Showing the last known quota."
            )
            else -> RefreshFailure(
                retryable = false,
                userMessage = raw.takeIf { it.isNotBlank() } ?: "Quota refresh failed."
            )
        }
    }

    private data class RefreshFailure(
        val retryable: Boolean,
        val userMessage: String
    )

    companion object {
        const val KEY_APP_WIDGET_ID = "app_widget_id"
        private const val MAX_RETRY_ATTEMPTS = 4
        private val HTTP_STATUS_REGEX = Regex("(?:HTTP|http)\\s+(\\d{3})")
    }
}
