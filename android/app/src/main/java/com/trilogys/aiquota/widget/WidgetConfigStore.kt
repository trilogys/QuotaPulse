package com.trilogys.aiquota.widget

import android.content.Context
import com.trilogys.aiquota.core.ProviderId

class WidgetConfigStore(context: Context) {
    private val prefs = context.getSharedPreferences("aiquota_widget_config", Context.MODE_PRIVATE)

    data class Config(
        val mode: Mode = Mode.ALL,
        val provider: ProviderId? = null,
        val accountId: String? = null
    )

    enum class Mode { ALL, PROVIDER, ACCOUNT }

    fun get(appWidgetId: Int): Config {
        val mode = runCatching { Mode.valueOf(prefs.getString("$appWidgetId.mode", Mode.ALL.name) ?: Mode.ALL.name) }
            .getOrDefault(Mode.ALL)
        val provider = prefs.getString("$appWidgetId.provider", null)?.let {
            runCatching { ProviderId.valueOf(it) }.getOrNull()
        }
        val accountId = prefs.getString("$appWidgetId.account", null)
        return Config(mode, provider, accountId)
    }

    fun save(appWidgetId: Int, config: Config) {
        prefs.edit()
            .putString("$appWidgetId.mode", config.mode.name)
            .putString("$appWidgetId.provider", config.provider?.name)
            .putString("$appWidgetId.account", config.accountId)
            .apply()
    }

    fun delete(appWidgetId: Int) {
        prefs.edit()
            .remove("$appWidgetId.mode")
            .remove("$appWidgetId.provider")
            .remove("$appWidgetId.account")
            .apply()
    }
}
