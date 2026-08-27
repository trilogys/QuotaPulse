package com.trilogys.aiquota.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.width
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
        val rows = store.accounts().filter { it.enabled }.take(6).map { it to store.snapshot(it.id) }
        provideContent { WidgetContent(rows) }
    }
}

class AIQuotaWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AIQuotaWidget()
}

@Composable
private fun WidgetContent(rows: List<Pair<AccountRecord, UsageSnapshot?>>) {
    Column(GlanceModifier.fillMaxSize().padding(12.dp)) {
        Row {
            Text("AI QUOTA", style = TextStyle(fontWeight = FontWeight.Bold))
            Text("  ↻", modifier = GlanceModifier.clickable(actionRunCallback<RefreshWidgetAction>()))
        }
        Spacer(GlanceModifier.width(4.dp))
        if (rows.isEmpty()) {
            Text("打开 AIQuota 添加账号")
        } else {
            rows.forEach { (account, snapshot) ->
                Row {
                    Text("${account.name}  ", style = TextStyle(fontWeight = FontWeight.Medium))
                    Text(summary(snapshot))
                }
            }
            val latest = rows.mapNotNull { it.second?.updatedAtEpochSeconds }.maxOrNull()
            if (latest != null) {
                Text("更新 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(latest * 1000))}")
            }
        }
    }
}

private fun summary(snapshot: UsageSnapshot?): String {
    if (snapshot == null) return "--"
    if (snapshot.stale) return "⚠ ${snapshot.windows.firstOrNull()?.remainingPercent?.roundToInt() ?: "--"}%"
    snapshot.balance?.let { return "${it.symbol}${"%.2f".format(it.total)}" }
    return snapshot.windows.take(2).joinToString(" · ") { "${it.label} ${it.remainingPercent.roundToInt()}%" }
}
