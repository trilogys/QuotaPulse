package com.trilogys.aiquota.work

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.trilogys.aiquota.core.AccountStore
import com.trilogys.aiquota.core.CredentialStore
import com.trilogys.aiquota.core.UsageService
import com.trilogys.aiquota.widget.AIQuotaWidget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class QuotaRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val accountStore = AccountStore(applicationContext)
        val usageService = UsageService(CredentialStore(applicationContext))
        var hadSuccess = false
        accountStore.accounts().filter { it.enabled }.forEach { account ->
            runCatching { usageService.refresh(account) }
                .onSuccess { accountStore.saveSnapshot(it); hadSuccess = true }
                .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
        }
        AIQuotaWidget().updateAll(applicationContext)
        if (hadSuccess || accountStore.accounts().isEmpty()) Result.success() else Result.retry()
    }
}
