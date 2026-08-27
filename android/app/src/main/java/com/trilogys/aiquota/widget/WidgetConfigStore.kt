package com.trilogys.aiquota.widget

import android.content.Context
import com.trilogys.aiquota.core.ProviderId

class WidgetConfigStore(context: Context) {
    private val prefs = context.getSharedPreferences("aiquota_widget_config", Context.MODE_PRIVATE)

    data class Config(
        val mode: Mode = Mode.ALL,
        val provider: ProviderId? = null,
        val accountId: String? = null,
        val layout: Layout = Layout.COMPACT,
        val maxRows: Int = 4
    )

    enum class Mode { ALL, PROVIDER, ACCOUNT }
    enum class Layout { COMPACT, DETAILED }

    fun get(appWidgetId: Int): Config {
        val mode = runCatching { Mode.valueOf(prefs.getString("$appWidgetId.mode", Mode.ALL.name) ?: Mode.ALL.name) }
            .getOrDefault(Mode.ALL)
        val provider = prefs.getString("$appWidgetId.provider", null)?.let {
            runCatching { ProviderId.valueOf(it) }.getOrNull()
        }
        val accountId = prefs.getString("$appWidgetId.account", null)
        val layout = runCatching {
            Layout.valueOf(prefs.getString("$appWidgetId.layout", Layout.COMPACT.name) ?: Layout.COMPACT.name)
        }.getOrDefault(Layout.COMPACT)
        val maxRows = prefs.getInt("$appWidgetId.maxRows", 4).coerceIn(1, 8)
        return Config(mode, provider, accountId, layout, maxRows)
    }

    fun save(appWidgetId: Int, config: Config) {
        prefs.edit()
            .putString("$appWidgetId.mode", config.mode.name)
            .putString("$appWidgetId.provider", config.provider?.name)
            .putString("$appWidgetId.account", config.accountId)
            .putString("$appWidgetId.layout", config.layout.name)
            .putInt("$appWidgetId.maxRows", config.maxRows.coerceIn(1, 8))
            .apply()
    }

    fun delete(appWidgetId: Int) {
        prefs.edit()
            .remove("$appWidgetId.mode")
            .remove("$appWidgetId.provider")
            .remove("$appWidgetId.account")
            .remove("$appWidgetId.layout")
            .remove("$appWidgetId.maxRows")
            .apply()
    }
}
