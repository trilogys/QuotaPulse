package com.trilogys.aiquota.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.layout.*
import androidx.glance.text.*
import com.trilogys.aiquota.R
import com.trilogys.aiquota.core.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

class AIQuotaWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = AccountStore(context); val configStore = WidgetConfigStore(context); val appWidgetId = (id as? AppWidgetId)?.appWidgetId
        val config = appWidgetId?.let(configStore::get) ?: WidgetConfigStore.Config()
        val accounts = store.accounts().filter { it.enabled }.filter { account -> when (config.mode) { WidgetConfigStore.Mode.ALL -> true; WidgetConfigStore.Mode.PROVIDER -> account.provider == config.provider; WidgetConfigStore.Mode.ACCOUNT -> account.id == config.accountId } }.take(config.maxRows)
        provideContent { WidgetContent(accounts.map { it to store.snapshot(it.id) }, config.layout) }
    }
}
class AIQuotaWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = AIQuotaWidget(); override fun onDeleted(context: Context, appWidgetIds: IntArray) { super.onDeleted(context, appWidgetIds); val store = WidgetConfigStore(context); appWidgetIds.forEach(store::delete) } }

@Composable private fun WidgetContent(rows: List<Pair<AccountRecord, UsageSnapshot?>>, requestedLayout: WidgetConfigStore.Layout) {
    val context = LocalContext.current; val size = LocalSize.current; val compactBySize = size.width < 180.dp || size.height < 140.dp; val layout = if (compactBySize) WidgetConfigStore.Layout.COMPACT else requestedLayout
    val adaptiveRows = when { size.height < 110.dp -> 1; size.height < 170.dp -> 2; size.height < 250.dp -> 4; else -> 8 }; val visibleRows = rows.take(adaptiveRows)
    Column(GlanceModifier.fillMaxSize().padding(if (compactBySize) 9.dp else 12.dp)) {
        Row { Text(context.getString(R.string.widget_title), style = TextStyle(fontWeight = FontWeight.Bold)); Text("  ↻", modifier = GlanceModifier.clickable(actionRunCallback<RefreshWidgetAction>())) }; Spacer(GlanceModifier.height(if (compactBySize) 4.dp else 6.dp))
        if (visibleRows.isEmpty()) Text(context.getString(R.string.widget_empty)) else { visibleRows.forEach { (account, snapshot) -> if (layout == WidgetConfigStore.Layout.COMPACT) CompactAccountRow(context, account, snapshot) else DetailedAccountRow(context, account, snapshot); Spacer(GlanceModifier.height(if (layout == WidgetConfigStore.Layout.DETAILED) 6.dp else 3.dp)) }; visibleRows.mapNotNull { it.second?.updatedAtEpochSeconds }.maxOrNull()?.let { Text(context.getString(R.string.updated, formatTime(it))) } }
    }
}
@Composable private fun CompactAccountRow(context: Context, account: AccountRecord, snapshot: UsageSnapshot?) { Row { Text("${account.name}  ", style = TextStyle(fontWeight = FontWeight.Medium)); Text(summary(context, snapshot)) } }
@Composable private fun DetailedAccountRow(context: Context, account: AccountRecord, snapshot: UsageSnapshot?) { Column { Text("${account.provider.name} · ${account.name}", style = TextStyle(fontWeight = FontWeight.Medium)); if (snapshot == null) Text(context.getString(R.string.no_data)) else { val kind = snapshot.errorKind ?: snapshot.errorMessage?.let(ProviderErrorClassifier::classify); if (kind != null && (snapshot.stale || snapshot.errorMessage != null)) Text(healthLabel(context, snapshot, kind)); if (snapshot.balance != null) Text("${context.getString(R.string.balance)} ${snapshot.balance.symbol}${"%.2f".format(snapshot.balance.total)}") else if (snapshot.windows.isNotEmpty()) Text(snapshot.windows.take(2).joinToString(" · ") { val reset = it.resetAtEpochSeconds?.let(::formatCountdown); if (reset == null) "${it.label} ${it.remainingPercent.roundToInt()}%" else "${it.label} ${it.remainingPercent.roundToInt()}% · ${context.getString(R.string.reset_in, reset)}" }) } } }
private fun healthText(context: Context, kind: ProviderErrorKind): String = context.getString(when (kind) { ProviderErrorKind.AUTHENTICATION -> R.string.health_authentication; ProviderErrorKind.RATE_LIMITED -> R.string.health_rate_limited; ProviderErrorKind.PROVIDER_UNAVAILABLE -> R.string.health_provider_unavailable; ProviderErrorKind.NETWORK -> R.string.health_network; ProviderErrorKind.INVALID_RESPONSE -> R.string.health_invalid_response; ProviderErrorKind.CONFIGURATION -> R.string.health_configuration; ProviderErrorKind.UNKNOWN -> R.string.health_unknown })
private fun healthLabel(context: Context, snapshot: UsageSnapshot, kind: ProviderErrorKind): String { val icon = when (kind) { ProviderErrorKind.AUTHENTICATION -> "🔐"; ProviderErrorKind.RATE_LIMITED -> "⏳"; ProviderErrorKind.PROVIDER_UNAVAILABLE -> "☁"; ProviderErrorKind.NETWORK -> "⌁"; ProviderErrorKind.INVALID_RESPONSE -> "⚠"; ProviderErrorKind.CONFIGURATION -> "⚙"; ProviderErrorKind.UNKNOWN -> "⚠" }; val label = healthText(context, kind); val cached = snapshot.windows.isNotEmpty() || snapshot.balance != null; return "$icon ${if (cached) context.getString(R.string.health_cached, label) else label}" }
private fun summary(context: Context, snapshot: UsageSnapshot?): String { if (snapshot == null) return "--"; val kind = snapshot.errorKind ?: snapshot.errorMessage?.let(ProviderErrorClassifier::classify); if (kind != null && snapshot.stale) return "${healthText(context, kind)} · ${snapshot.windows.firstOrNull()?.remainingPercent?.roundToInt() ?: "--"}%"; snapshot.balance?.let { return "${it.symbol}${"%.2f".format(it.total)}" }; return snapshot.windows.take(2).joinToString(" · ") { "${it.label} ${it.remainingPercent.roundToInt()}%" } }
private fun formatCountdown(epochSeconds: Long): String { val remaining = (epochSeconds - System.currentTimeMillis() / 1000).coerceAtLeast(0); val days = remaining / 86400; val hours = (remaining % 86400) / 3600; val minutes = (remaining % 3600) / 60; return when { days > 0 -> "${days}d ${hours}h"; hours > 0 -> "${hours}h ${minutes}m"; else -> "${minutes.coerceAtLeast(1)}m" } }
private fun formatTime(epochSeconds: Long): String = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochSeconds * 1000))
