package com.trilogys.aiquota

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.updateAll
import com.trilogys.aiquota.core.AccountRecord
import com.trilogys.aiquota.core.AccountStore
import com.trilogys.aiquota.core.Credential
import com.trilogys.aiquota.core.CredentialStore
import com.trilogys.aiquota.core.ProviderId
import com.trilogys.aiquota.core.UsageService
import com.trilogys.aiquota.widget.AIQuotaWidget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                AIQuotaScreen(
                    accountStore = remember { AccountStore(this) },
                    credentialStore = remember { CredentialStore(this) },
                    usageService = remember { UsageService(CredentialStore(this)) },
                    updateWidget = { AIQuotaWidget().updateAll(this) }
                )
            }
        }
    }
}

@Composable
private fun AIQuotaScreen(
    accountStore: AccountStore,
    credentialStore: CredentialStore,
    usageService: UsageService,
    updateWidget: suspend () -> Unit
) {
    val scope = rememberCoroutineScope()
    var accounts by remember { mutableStateOf(accountStore.accounts()) }
    var selectedProvider by remember { mutableStateOf(ProviderId.DEEPSEEK) }
    var name by remember { mutableStateOf("") }
    var accessToken by remember { mutableStateOf("") }
    var refreshToken by remember { mutableStateOf("") }
    var accountId by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }

    fun reload() { accounts = accountStore.accounts() }

    Scaffold { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text("AIQuota", style = MaterialTheme.typography.headlineMedium)
                Text("iOS + Android · 多账号 · 桌面额度小组件")
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ProviderId.entries.forEach { provider ->
                        TextButton(onClick = { selectedProvider = provider }) {
                            Text(if (selectedProvider == provider) "● ${provider.name}" else provider.name)
                        }
                    }
                }
                OutlinedTextField(name, { name = it }, label = { Text("账号名称") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(accessToken, { accessToken = it }, label = { Text(if (selectedProvider == ProviderId.DEEPSEEK) "API Key" else "Access Token") }, modifier = Modifier.fillMaxWidth())
                if (selectedProvider != ProviderId.DEEPSEEK) {
                    OutlinedTextField(refreshToken, { refreshToken = it }, label = { Text("Refresh Token（推荐）") }, modifier = Modifier.fillMaxWidth())
                }
                if (selectedProvider == ProviderId.CODEX) {
                    OutlinedTextField(accountId, { accountId = it }, label = { Text("ChatGPT Account ID（可选）") }, modifier = Modifier.fillMaxWidth())
                }
                Button(
                    enabled = accessToken.isNotBlank(),
                    onClick = {
                        val account = AccountRecord(provider = selectedProvider, name = name.ifBlank { selectedProvider.name })
                        accountStore.upsert(account)
                        credentialStore.save(account.id, Credential(accessToken.trim(), refreshToken.trim().ifBlank { null }, accountId = accountId.trim().ifBlank { null }))
                        accessToken = ""; refreshToken = ""; accountId = ""; name = ""; status = "已添加 ${account.name}"; reload()
                        scope.launch { updateWidget() }
                    }
                ) { Text("添加账号") }
                if (status.isNotBlank()) Text(status)
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    scope.launch {
                        status = "正在刷新…"
                        withContext(Dispatchers.IO) {
                            accountStore.accounts().filter { it.enabled }.forEach { account ->
                                runCatching { usageService.refresh(account) }
                                    .onSuccess(accountStore::saveSnapshot)
                                    .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
                            }
                        }
                        updateWidget(); status = "刷新完成"; reload()
                    }
                }) { Text("刷新全部") }
            }

            items(accounts, key = { it.id }) { account ->
                val snapshot = accountStore.snapshot(account.id)
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text("${account.provider.name} · ${account.name}", style = MaterialTheme.typography.titleMedium)
                        val summary = snapshot?.balance?.let { "${it.symbol}${"%.2f".format(it.total)}" }
                            ?: snapshot?.windows?.joinToString("  ") { "${it.label} ${it.remainingPercent.roundToInt()}%" }
                            ?: "尚未刷新"
                        Text(summary)
                        snapshot?.errorMessage?.let { Text("⚠ $it") }
                        Row {
                            TextButton(onClick = {
                                scope.launch {
                                    status = "刷新 ${account.name}…"
                                    withContext(Dispatchers.IO) {
                                        runCatching { usageService.refresh(account) }
                                            .onSuccess(accountStore::saveSnapshot)
                                            .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
                                    }
                                    updateWidget(); status = "完成"
                                }
                            }) { Text("刷新") }
                            TextButton(onClick = {
                                accountStore.delete(account.id); credentialStore.delete(account.id); reload(); scope.launch { updateWidget() }
                            }) { Text("删除") }
                        }
                    }
                }
            }
        }
    }
}
