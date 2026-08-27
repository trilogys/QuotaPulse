package com.trilogys.aiquota

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.annotation.StringRes
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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
    val context = LocalContext.current
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
                status = context.getString(R.string.reauth_success, existing.name)
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
        selectedProvider = account.provider
        reauthAccountId = account.id
        name = account.name
        oauthPaste = ""
        status = if (account.provider == ProviderId.DEEPSEEK) {
            context.getString(R.string.reauth_api_key, account.name)
        } else {
            context.getString(R.string.reauth_in_progress, account.name)
        }
    }

    val recommended = recommendedAccountIds(accounts, accountStore)

    Scaffold { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineMedium)
                Text(stringResource(R.string.app_subtitle))
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ProviderId.entries.forEach { provider ->
                        TextButton(onClick = { selectedProvider = provider; oauthPaste = ""; reauthAccountId = null }) {
                            Text(if (selectedProvider == provider) "● ${provider.name}" else provider.name)
                        }
                    }
                }
                if (reauthAccountId != null) {
                    Text(stringResource(R.string.reauth_mode))
                    TextButton(onClick = {
                        reauthAccountId = null; name = ""; oauthPaste = ""; status = context.getString(R.string.reauth_cancelled)
                    }) { Text(stringResource(R.string.cancel_reauth)) }
                }
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.account_name_optional)) }, modifier = Modifier.fillMaxWidth())

                when (selectedProvider) {
                    ProviderId.CODEX -> {
                        Button(onClick = {
                            status = context.getString(R.string.codex_open_browser)
                            scope.launch {
                                runCatching { oauth.loginCodex() }
                                    .onSuccess { saveCredential(ProviderId.CODEX, it) }
                                    .onFailure { status = context.getString(R.string.codex_manual_fallback, it.message ?: "OAuth failed") }
                            }
                        }) { Text(stringResource(if (reauthAccountId != null) R.string.codex_relogin else R.string.codex_login)) }
                        OutlinedTextField(
                            oauthPaste,
                            { oauthPaste = it },
                            label = { Text(stringResource(R.string.codex_callback_hint)) },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Button(enabled = oauthPaste.isNotBlank(), onClick = {
                            scope.launch {
                                runCatching { oauth.completeCodexManual(oauthPaste) }
                                    .onSuccess { saveCredential(ProviderId.CODEX, it); oauthPaste = "" }
                                    .onFailure { status = it.message ?: "Codex callback failed" }
                            }
                        }) { Text(stringResource(R.string.codex_callback)) }
                    }
                    ProviderId.CLAUDE -> {
                        Button(onClick = {
                            oauth.beginClaude()
                            status = context.getString(R.string.claude_paste_code)
                        }) { Text(stringResource(if (reauthAccountId != null) R.string.claude_relogin else R.string.claude_login)) }
                        OutlinedTextField(
                            oauthPaste,
                            { oauthPaste = it },
                            label = { Text(stringResource(R.string.claude_code_hint)) },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Button(enabled = oauthPaste.isNotBlank(), onClick = {
                            scope.launch {
                                runCatching { oauth.completeClaude(oauthPaste) }
                                    .onSuccess { saveCredential(ProviderId.CLAUDE, it); oauthPaste = "" }
                                    .onFailure { status = it.message ?: "Claude OAuth failed" }
                            }
                        }) { Text(stringResource(R.string.claude_complete)) }
                    }
                    ProviderId.KIMI -> {
                        Button(onClick = {
                            status = context.getString(R.string.kimi_starting)
                            scope.launch {
                                runCatching { oauth.loginKimi() }
                                    .onSuccess { saveCredential(ProviderId.KIMI, it) }
                                    .onFailure { status = it.message ?: "Kimi OAuth failed" }
                            }
                        }) { Text(stringResource(if (reauthAccountId != null) R.string.kimi_relogin else R.string.kimi_login)) }
                    }
                    ProviderId.DEEPSEEK -> Unit
                }

                Text(stringResource(R.string.oauth_fallback))
                OutlinedTextField(
                    accessToken,
                    { accessToken = it },
                    label = { Text(stringResource(if (selectedProvider == ProviderId.DEEPSEEK) R.string.api_key else R.string.access_token)) },
                    modifier = Modifier.fillMaxWidth()
                )
                if (selectedProvider != ProviderId.DEEPSEEK) {
                    OutlinedTextField(refreshToken, { refreshToken = it }, label = { Text(stringResource(R.string.refresh_token)) }, modifier = Modifier.fillMaxWidth())
                }
                if (selectedProvider == ProviderId.CODEX) {
                    OutlinedTextField(accountId, { accountId = it }, label = { Text(stringResource(R.string.account_id_optional)) }, modifier = Modifier.fillMaxWidth())
                }
                Button(enabled = accessToken.isNotBlank(), onClick = {
                    saveCredential(selectedProvider, Credential(
                        accessToken = accessToken.trim(),
                        refreshToken = refreshToken.trim().ifBlank { null },
                        accountId = accountId.trim().ifBlank { null }
                    ))
                    accessToken = ""; refreshToken = ""; accountId = ""
                }) { Text(stringResource(if (reauthAccountId != null) R.string.update_credentials else R.string.import_credentials)) }

                if (status.isNotBlank()) Text(status)
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    scope.launch {
                        status = context.getString(R.string.refreshing)
                        withContext(Dispatchers.IO) {
                            accountStore.accounts().filter { it.enabled }.forEach { account ->
                                runCatching { usageService.refresh(account) }
                                    .onSuccess(accountStore::saveSnapshot)
                                    .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
                            }
                        }
                        updateWidget(); status = context.getString(R.string.refresh_complete); reload()
                    }
                }) { Text(stringResource(R.string.refresh_all)) }
            }

            items(accounts, key = { it.id }) { account ->
                val snapshot = accountStore.snapshot(account.id)
                val health = stringResource(credentialHealthRes(account, credentialStore, snapshot?.stale == true))
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        val recommendedMark = if (recommended.contains(account.id)) " ★ ${stringResource(R.string.recommended)}" else ""
                        val hiddenMark = if (!account.enabled) " · ${stringResource(R.string.hidden)}" else ""
                        Text("${account.provider.name} · ${account.name}$recommendedMark$hiddenMark", style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(R.string.credential_status, health))
                        val summary = snapshot?.balance?.let { "${it.symbol}${"%.2f".format(it.total)}" }
                            ?: snapshot?.windows?.joinToString("  ") { window ->
                                val reset = window.resetAtEpochSeconds?.let(::formatCountdown)
                                if (reset == null) "${window.label} ${window.remainingPercent.roundToInt()}%"
                                else "${window.label} ${window.remainingPercent.roundToInt()}% ↻$reset"
                            } ?: stringResource(R.string.no_data)
                        Text(summary)
                        snapshot?.errorMessage?.let { Text("⚠ $it") }
                        Row {
                            TextButton(onClick = {
                                scope.launch {
                                    status = "${context.getString(R.string.refresh)} ${account.name}…"
                                    withContext(Dispatchers.IO) {
                                        runCatching { usageService.refresh(account) }
                                            .onSuccess(accountStore::saveSnapshot)
                                            .onFailure { accountStore.markStale(account.id, it.message ?: "Refresh failed") }
                                    }
                                    updateWidget(); status = context.getString(R.string.refresh_complete); reload()
                                }
                            }) { Text(stringResource(R.string.refresh)) }
                            TextButton(onClick = { beginReauth(account) }) { Text(stringResource(R.string.reauthenticate)) }
                            TextButton(onClick = {
                                accountStore.setEnabled(account.id, !account.enabled); reload(); scope.launch { updateWidget() }
                            }) { Text(stringResource(if (account.enabled) R.string.hide else R.string.show)) }
                            TextButton(onClick = { accountStore.move(account.id, -1); reload(); scope.launch { updateWidget() } }) { Text("↑") }
                            TextButton(onClick = { accountStore.move(account.id, 1); reload(); scope.launch { updateWidget() } }) { Text("↓") }
                            TextButton(onClick = {
                                accountStore.delete(account.id); credentialStore.delete(account.id); reload(); scope.launch { updateWidget() }
                            }) { Text(stringResource(R.string.delete)) }
                        }
                    }
                }
            }
        }
    }
}

@StringRes
private fun credentialHealthRes(account: AccountRecord, store: CredentialStore, stale: Boolean): Int {
    val credential = store.get(account.id) ?: return R.string.credential_sign_in_again
    if (account.provider == ProviderId.DEEPSEEK) return if (stale) R.string.credential_cached else R.string.credential_healthy
    val expiry = credential.expiresAtEpochSeconds
    if (expiry != null) {
        val now = System.currentTimeMillis() / 1000
        if (expiry <= now) return if (!credential.refreshToken.isNullOrBlank()) R.string.credential_refreshable else R.string.credential_sign_in_again
        if (expiry - now < 3600) return R.string.credential_renew_soon
    }
    return if (stale) R.string.credential_cached else R.string.credential_healthy
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
