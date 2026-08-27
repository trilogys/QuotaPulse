package com.trilogys.aiquota.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.AppWidgetId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.trilogys.aiquota.core.AccountRecord
import com.trilogys.aiquota.core.AccountStore
import com.trilogys.aiquota.core.UsageSnapshot
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

class AIQuotaWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = AccountStore(context)
        val configStore = WidgetConfigStore(context)
        val appWidgetId = (id as? AppWidgetId)?.appWidgetId
        val config = appWidgetId?.let(configStore::get) ?: WidgetConfigStore.Config()
        val accounts = store.accounts().filter { it.enabled }.filter { account ->
            when (config.mode) {
                WidgetConfigStore.Mode.ALL -> true
                WidgetConfigStore.Mode.PROVIDER -> account.provider == config.provider
                WidgetConfigStore.Mode.ACCOUNT -> account.id == config.accountId
            }
        }.take(config.maxRows)
        val rows = accounts.map { it to store.snapshot(it.id) }
        provideContent { WidgetContent(rows, config.layout) }
    }
}

class AIQuotaWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AIQuotaWidget()

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val store = WidgetConfigStore(context)
        appWidgetIds.forEach(store::delete)
    }
}

@Composable
private fun WidgetContent(
    rows: List<Pair<AccountRecord, UsageSnapshot?>>,
    layout: WidgetConfigStore.Layout
) {
    Column(GlanceModifier.fillMaxSize().padding(12.dp)) {
        Row {
            Text("AI QUOTA", style = TextStyle(fontWeight = FontWeight.Bold))
            Text("  ↻", modifier = GlanceModifier.clickable(actionRunCallback<RefreshWidgetAction>()))
        }
        Spacer(GlanceModifier.height(6.dp))
        if (rows.isEmpty()) {
            Text("暂无匹配账号，长按小组件重新配置")
        } else {
            rows.forEach { (account, snapshot) ->
                when (layout) {
                    WidgetConfigStore.Layout.COMPACT -> CompactAccountRow(account, snapshot)
                    WidgetConfigStore.Layout.DETAILED -> DetailedAccountRow(account, snapshot)
                }
                Spacer(GlanceModifier.height(if (layout == WidgetConfigStore.Layout.DETAILED) 6.dp else 3.dp))
            }
            val latest = rows.mapNotNull { it.second?.updatedAtEpochSeconds }.maxOrNull()
            if (latest != null) {
                Text("更新 ${formatTime(latest)}")
            }
        }
    }
}

@Composable
private fun CompactAccountRow(account: AccountRecord, snapshot: UsageSnapshot?) {
    Row {
        Text("${account.name}  ", style = TextStyle(fontWeight = FontWeight.Medium))
        Text(summary(snapshot))
    }
}

@Composable
private fun DetailedAccountRow(account: AccountRecord, snapshot: UsageSnapshot?) {
    Column {
        Text(
            "${account.provider.name} · ${account.name}",
            style = TextStyle(fontWeight = FontWeight.Medium)
        )
        if (snapshot == null) {
            Text("尚未刷新")
        } else if (snapshot.stale) {
            Text("⚠ 缓存 · ${summary(snapshot)}")
        } else if (snapshot.balance != null) {
            Text("余额 ${snapshot.balance.symbol}${"%.2f".format(snapshot.balance.total)}")
        } else {
            Text(snapshot.windows.take(2).joinToString(" · ") {
                val reset = it.resetAtEpochSeconds?.let(::formatTime)
                if (reset == null) "${it.label} ${it.remainingPercent.roundToInt()}%"
                else "${it.label} ${it.remainingPercent.roundToInt()}% ↻$reset"
            })
        }
    }
}

private fun summary(snapshot: UsageSnapshot?): String {
    if (snapshot == null) return "--"
    if (snapshot.stale) return "⚠ ${snapshot.windows.firstOrNull()?.remainingPercent?.roundToInt() ?: "--"}%"
    snapshot.balance?.let { return "${it.symbol}${"%.2f".format(it.total)}" }
    return snapshot.windows.take(2).joinToString(" · ") { "${it.label} ${it.remainingPercent.roundToInt()}%" }
}

private fun formatTime(epochSeconds: Long): String =
    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochSeconds * 1000))
