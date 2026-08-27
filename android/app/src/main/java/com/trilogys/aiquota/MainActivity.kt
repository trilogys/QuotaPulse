package com.trilogys.aiquota

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
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
import com.trilogys.aiquota.auth.OAuthManager
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
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
        setContent {
            MaterialTheme {
                val credentialStore = remember { CredentialStore(this) }
                AIQuotaScreen(
                    accountStore = remember { AccountStore(this) },
                    credentialStore = credentialStore,
                    usageService = remember { UsageService(credentialStore) },
                    oauth = remember { OAuthManager(this) },
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
    oauth: OAuthManager,
    updateWidget: suspend () -> Unit
) {
    val scope = rememberCoroutineScope()
    var accounts by remember { mutableStateOf(accountStore.accounts()) }
    var selectedProvider by remember { mutableStateOf(ProviderId.CODEX) }
    var name by remember { mutableStateOf("") }
    var accessToken by remember { mutableStateOf("") }
    var refreshToken by remember { mutableStateOf("") }
    var accountId by remember { mutableStateOf("") }
    var oauthPaste by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var reauthAccountId by remember { mutableStateOf<String?>(null) }

    fun reload() { accounts = accountStore.accounts() }
    fun saveCredential(provider: ProviderId, credential: Credential) {
        val replacingId = reauthAccountId
        if (replacingId != null) {
            val existing = accounts.firstOrNull { it.id == replacingId }
            if (existing != null) {
                credentialStore.save(existing.id, credential)
                reauthAccountId = null
                name = ""
                status = "${existing.name} 重新认证成功"
                scope.launch {
                    withContext(Dispatchers.IO) {
                        runCatching { usageService.refresh(existing) }
                            .onSuccess(accountStore::saveSnapshot)
                            .onFailure { accountStore.markStale(existing.id, it.message ?: "Refresh failed") }
                    }
                    updateWidget(); reload()
                }
                return
            }
            reauthAccountId = null
        }
        val account = AccountRecord(provider = provider, name = name.ifBlank { provider.name })
        accountStore.upsert(account)
        credentialStore.save(account.id, credential)
        name = ""
        reload()
        scope.launch { updateWidget() }
    }

    fun beginReauth(account: AccountRecord) {
        if (account.provider == ProviderId.DEEPSEEK) {
            selectedProvider = ProviderId.DEEPSEEK
            reauthAccountId = account.id
            name = account.name
            status = "请重新输入 ${account.name} 的 API Key"
        } else {
            selectedProvider = account.provider
            reauthAccountId = account.id
            name = account.name
            oauthPaste = ""
            status = "正在重新认证 ${account.name}；完成后会覆盖原凭据，不会新增账号。"
        }
    }

    val recommended = recommendedAccountIds(accounts, accountStore)

    Scaffold { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text("AIQuota", style = MaterialTheme.typography.headlineMedium)
                Text("原生 Android · 多账号 · OAuth · 桌面小组件")
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ProviderId.entries.forEach { provider ->
                        TextButton(onClick = { selectedProvider = provider; oauthPaste = ""; reauthAccountId = null }) {
                            Text(if (selectedProvider == provider) "● ${provider.name}" else provider.name)
                        }
                    }
                }
                if (reauthAccountId != null) {
                    Text("重新认证模式：成功后覆盖原账号凭据")
                    TextButton(onClick = { reauthAccountId = null; name = ""; oauthPaste = ""; status = "已取消重新认证" }) { Text("取消重新认证") }
                }
                OutlinedTextField(name, { name = it }, label = { Text("账号名称（可选）") }, modifier = Modifier.fillMaxWidth())

                when (selectedProvider) {
                    ProviderId.CODEX -> {
                        Button(onClick = {
                            status = "请在浏览器登录 Codex；完成后会自动回到本机 localhost。"
                            scope.launch {
                                runCatching { oauth.loginCodex() }
                                    .onSuccess { saveCredential(ProviderId.CODEX, it); if (reauthAccountId == null) status = "Codex OAuth 完成" }
                                    .onFailure { status = "自动回调未完成：${it.message}\n可复制 localhost 完整地址到下方手动完成。" }
                            }
                        }) { Text(if (reauthAccountId != null) "重新登录 Codex" else "Codex OAuth 登录") }
                        OutlinedTextField(oauthPaste, { oauthPaste = it }, label = { Text("localhost callback URL（自动回调失败时）") }, modifier = Modifier.fillMaxWidth())
                        Button(enabled = oauthPaste.isNotBlank(), onClick = {
                            scope.launch {
                                runCatching { oauth.completeCodexManual(oauthPaste) }
                                    .onSuccess { saveCredential(ProviderId.CODEX, it); oauthPaste = "" }
                                    .onFailure { status = it.message ?: "Codex callback failed" }
                            }
                        }) { Text("完成 Codex 回调") }
                    }
                    ProviderId.CLAUDE -> {
                        Button(onClick = {
                            oauth.beginClaude()
                            status = "Claude 授权完成后，把页面显示的 CODE#STATE 粘贴到下方。"
                        }) { Text(if (reauthAccountId != null) "重新登录 Claude" else "Claude OAuth 登录") }
                        OutlinedTextField(oauthPaste, { oauthPaste = it }, label = { Text("Claude CODE#STATE") }, modifier = Modifier.fillMaxWidth())
                        Button(enabled = oauthPaste.isNotBlank(), onClick = {
                            scope.launch {
                                runCatching { oauth.completeClaude(oauthPaste) }
                                    .onSuccess { saveCredential(ProviderId.CLAUDE, it); oauthPaste = "" }
                                    .onFailure { status = it.message ?: "Claude OAuth failed" }
                            }
                        }) { Text("完成 Claude 授权") }
                    }
                    ProviderId.KIMI -> {
                        Button(onClick = {
                            status = "正在启动 Kimi Device OAuth…"
                            scope.launch {
                                runCatching { oauth.loginKimi() }
                                    .onSuccess { saveCredential(ProviderId.KIMI, it) }
                                    .onFailure { status = it.message ?: "Kimi OAuth failed" }
                            }
                        }) { Text(if (reauthAccountId != null) "重新登录 Kimi" else "Kimi Device OAuth 登录") }
                    }
                    ProviderId.DEEPSEEK -> Unit
                }

                Text("高级/兜底：也可以直接导入已有凭据")
                OutlinedTextField(accessToken, { accessToken = it }, label = { Text(if (selectedProvider == ProviderId.DEEPSEEK) "API Key" else "Access Token") }, modifier = Modifier.fillMaxWidth())
                if (selectedProvider != ProviderId.DEEPSEEK) {
                    OutlinedTextField(refreshToken, { refreshToken = it }, label = { Text("Refresh Token（推荐）") }, modifier = Modifier.fillMaxWidth())
                }
                if (selectedProvider == ProviderId.CODEX) {
                    OutlinedTextField(accountId, { accountId = it }, label = { Text("ChatGPT Account ID（可选）") }, modifier = Modifier.fillMaxWidth())
                }
                Button(enabled = accessToken.isNotBlank(), onClick = {
                    saveCredential(selectedProvider, Credential(accessToken = accessToken.trim(), refreshToken = refreshToken.trim().ifBlank { null }, accountId = accountId.trim().ifBlank { null }))
                    accessToken = ""; refreshToken = ""; accountId = ""
                }) { Text(if (reauthAccountId != null) "更新凭据" else "导入凭据") }

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
                val health = credentialHealth(account, credentialStore, snapshot?.stale == true)
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        val recommendedMark = if (recommended.contains(account.id)) " ★ 推荐" else ""
                        val hiddenMark = if (!account.enabled) " · 已隐藏" else ""
                        Text("${account.provider.name} · ${account.name}$recommendedMark$hiddenMark", style = MaterialTheme.typography.titleMedium)
                        Text("凭据：$health")
                        val summary = snapshot?.balance?.let { "${it.symbol}${"%.2f".format(it.total)}" }
                            ?: snapshot?.windows?.joinToString("  ") { window ->
                                val reset = window.resetAtEpochSeconds?.let(::formatCountdown)
                                if (reset == null) "${window.label} ${window.remainingPercent.roundToInt()}%" else "${window.label} ${window.remainingPercent.roundToInt()}% ↻$reset"
                            } ?: "尚未刷新"
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
                                    updateWidget(); status = "完成"; reload()
                                }
                            }) { Text("刷新") }
                            TextButton(onClick = { beginReauth(account) }) { Text("重新认证") }
                            TextButton(onClick = { accountStore.setEnabled(account.id, !account.enabled); reload(); scope.launch { updateWidget() } }) { Text(if (account.enabled) "隐藏" else "显示") }
                            TextButton(onClick = { accountStore.move(account.id, -1); reload(); scope.launch { updateWidget() } }) { Text("↑") }
                            TextButton(onClick = { accountStore.move(account.id, 1); reload(); scope.launch { updateWidget() } }) { Text("↓") }
                            TextButton(onClick = { accountStore.delete(account.id); credentialStore.delete(account.id); reload(); scope.launch { updateWidget() } }) { Text("删除") }
                        }
                    }
                }
            }
        }
    }
}

private fun credentialHealth(account: AccountRecord, store: CredentialStore, stale: Boolean): String {
    val credential = store.get(account.id) ?: return "需重新认证"
    if (account.provider == ProviderId.DEEPSEEK) return if (stale) "已保存 · 数据缓存" else "正常"
    val expiry = credential.expiresAtEpochSeconds
    if (expiry != null) {
        val now = System.currentTimeMillis() / 1000
        if (expiry <= now) return if (!credential.refreshToken.isNullOrBlank()) "已过期 · 可自动续期" else "需重新认证"
        if (expiry - now < 3600) return "即将自动续期"
    }
    return if (stale) "凭据存在 · 数据缓存" else "正常"
}

private fun formatCountdown(epochSeconds: Long): String {
    val remaining = (epochSeconds - System.currentTimeMillis() / 1000).coerceAtLeast(0)
    val days = remaining / 86400
    val hours = (remaining % 86400) / 3600
    val minutes = (remaining % 3600) / 60
    return when {
        days > 0 -> "${days}d ${hours}h"
        hours > 0 -> "${hours}h ${minutes}m"
        else -> "${minutes.coerceAtLeast(1)}m"
    }
}

private fun recommendedAccountIds(accounts: List<AccountRecord>, store: AccountStore): Set<String> =
    ProviderId.entries.mapNotNull { provider ->
        accounts.asSequence().filter { it.enabled && it.provider == provider }.mapNotNull { account ->
            val snapshot = store.snapshot(account.id)?.takeUnless { it.stale } ?: return@mapNotNull null
            val score = snapshot.balance?.total ?: snapshot.windows.minOfOrNull { it.remainingPercent } ?: return@mapNotNull null
            account.id to score
        }.maxByOrNull { it.second }?.first
    }.toSet()
