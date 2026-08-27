package com.trilogys.aiquota.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.trilogys.aiquota.core.AccountStore
import com.trilogys.aiquota.core.ProviderId
import kotlinx.coroutines.launch

class WidgetConfigActivity : ComponentActivity() {
    private var appWidgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(Activity.RESULT_CANCELED)
        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContent {
            MaterialTheme {
                val accountStore = remember { AccountStore(this) }
                val configStore = remember { WidgetConfigStore(this) }
                val scope = rememberCoroutineScope()
                var config by remember { mutableStateOf(configStore.get(appWidgetId)) }
                val accounts = remember { accountStore.accounts().filter { it.enabled } }

                Column(Modifier.fillMaxSize().padding(16.dp)) {
                    Text("配置 AIQuota 小组件", style = MaterialTheme.typography.headlineSmall)
                    Text("每个小组件都可以独立选择显示内容。")

                    LazyColumn(
                        modifier = Modifier.weight(1f).fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        item {
                            ChoiceCard(
                                title = "全部账号",
                                selected = config.mode == WidgetConfigStore.Mode.ALL,
                                onClick = { config = WidgetConfigStore.Config(WidgetConfigStore.Mode.ALL) }
                            )
                        }
                        ProviderId.entries.forEach { provider ->
                            item {
                                ChoiceCard(
                                    title = "只显示 ${provider.name}",
                                    selected = config.mode == WidgetConfigStore.Mode.PROVIDER && config.provider == provider,
                                    onClick = {
                                        config = WidgetConfigStore.Config(
                                            mode = WidgetConfigStore.Mode.PROVIDER,
                                            provider = provider
                                        )
                                    }
                                )
                            }
                        }
                        if (accounts.isNotEmpty()) {
                            item { Text("单账号", style = MaterialTheme.typography.titleMedium) }
                            items(accounts, key = { it.id }) { account ->
                                ChoiceCard(
                                    title = "${account.provider.name} · ${account.name}",
                                    selected = config.mode == WidgetConfigStore.Mode.ACCOUNT && config.accountId == account.id,
                                    onClick = {
                                        config = WidgetConfigStore.Config(
                                            mode = WidgetConfigStore.Mode.ACCOUNT,
                                            accountId = account.id
                                        )
                                    }
                                )
                            }
                        }
                    }

                    Button(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            configStore.save(appWidgetId, config)
                            val result = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                            setResult(Activity.RESULT_OK, result)
                            scope.launch { AIQuotaWidget().updateAll(this@WidgetConfigActivity) }
                            finish()
                        }
                    ) { Text("保存") }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun ChoiceCard(title: String, selected: Boolean, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        TextButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
            Text(if (selected) "● $title" else "○ $title")
        }
    }
}
