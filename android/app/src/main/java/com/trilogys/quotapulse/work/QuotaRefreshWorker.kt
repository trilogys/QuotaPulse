package com.trilogys.quotapulse.work

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.trilogys.quotapulse.core.*
import com.trilogys.quotapulse.widget.QuotaPulseWidget
import com.trilogys.quotapulse.widget.WidgetConfigStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

class QuotaRefreshWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val store=AccountStore(applicationContext);val service=UsageService(CredentialStore(applicationContext));val notifier=QuotaNotifier(applicationContext);val widgetId=inputData.getInt(KEY_APP_WIDGET_ID,-1);val manual=inputData.getBoolean(KEY_MANUAL_REFRESH,false);val config=if(widgetId>=0)WidgetConfigStore(applicationContext).get(widgetId)else null
        val targets=store.accounts().filter{it.enabled}.filter{a->when(config?.mode){WidgetConfigStore.Mode.PROVIDER->a.provider==config.provider;WidgetConfigStore.Mode.ACCOUNT->a.id==config.accountId;WidgetConfigStore.Mode.ALL,null->true}}
        var success=false;var retryable=false
        targets.forEach{account->
            if(!manual&&store.cooldownUntil(account.id)!=null)return@forEach
            if(manual)store.clearCooldown(account.id)
            runCatching{service.refresh(account)}.onSuccess{store.clearCooldown(account.id);store.saveSnapshot(it.copy(stale=false,errorMessage=null,errorKind=null));notifier.evaluate(account,it);success=true}.onFailure{error->val failure=classifyFailure(error);store.markStale(account.id,failure.message,failure.kind);failure.cooldownSeconds?.let{store.setCooldown(account.id,System.currentTimeMillis()/1000+it)};if(failure.retryable)retryable=true}
        }
        QuotaPulseWidget().updateAll(applicationContext)
        when{targets.isEmpty()||success->Result.success();retryable&&runAttemptCount<MAX_RETRY_ATTEMPTS->Result.retry();else->Result.success()}
    }
    private fun classifyFailure(error:Throwable):RefreshFailure{val raw=error.message.orEmpty();val lower=raw.lowercase();val status=HTTP_STATUS_REGEX.find(raw)?.groupValues?.getOrNull(1)?.toIntOrNull();return when{
        status==401||status==403->RefreshFailure(false,ProviderErrorKind.AUTHENTICATION,"Authentication expired. Please sign in again.",AUTH_COOLDOWN);status==429->RefreshFailure(true,ProviderErrorKind.RATE_LIMITED,"Provider rate limit reached. Refresh will retry later.",RATE_LIMIT_COOLDOWN);status!=null&&status>=500->RefreshFailure(true,ProviderErrorKind.PROVIDER_UNAVAILABLE,"Provider is temporarily unavailable (HTTP $status).",SERVER_COOLDOWN);error is IOException->RefreshFailure(true,ProviderErrorKind.NETWORK,"Network or provider connection failed.",NETWORK_COOLDOWN);lower.contains("missing credential")->RefreshFailure(false,ProviderErrorKind.AUTHENTICATION,"Account credentials are missing. Please sign in again.",AUTH_COOLDOWN);lower.contains("json")||lower.contains("parse")||lower.contains("unexpected")->RefreshFailure(false,ProviderErrorKind.INVALID_RESPONSE,"Provider response format changed. Showing the last known quota.",FORMAT_COOLDOWN);lower.contains("configuration")||lower.contains("base url")->RefreshFailure(false,ProviderErrorKind.CONFIGURATION,raw.ifBlank{"Provider configuration is invalid."},CONFIG_COOLDOWN);else->RefreshFailure(false,ProviderErrorClassifier.classify(raw),raw.ifBlank{"Quota refresh failed."},UNKNOWN_COOLDOWN)}}
    private data class RefreshFailure(val retryable:Boolean,val kind:ProviderErrorKind,val message:String,val cooldownSeconds:Long?)
    companion object{const val KEY_APP_WIDGET_ID="app_widget_id";const val KEY_MANUAL_REFRESH="manual_refresh";private const val MAX_RETRY_ATTEMPTS=4;private const val RATE_LIMIT_COOLDOWN=15*60L;private const val SERVER_COOLDOWN=5*60L;private const val NETWORK_COOLDOWN=60L;private const val AUTH_COOLDOWN=6*60*60L;private const val FORMAT_COOLDOWN=60*60L;private const val CONFIG_COOLDOWN=60*60L;private const val UNKNOWN_COOLDOWN=5*60L;private val HTTP_STATUS_REGEX=Regex("(?:HTTP|http)\\s+(\\d{3})")}
}
