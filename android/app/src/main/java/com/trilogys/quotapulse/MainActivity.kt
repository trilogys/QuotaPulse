package com.trilogys.quotapulse

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.updateAll
import com.trilogys.quotapulse.auth.OAuthManager
import com.trilogys.quotapulse.core.AccountRecord
import com.trilogys.quotapulse.core.AccountStore
import com.trilogys.quotapulse.core.BalanceSnapshot
import com.trilogys.quotapulse.core.Credential
import com.trilogys.quotapulse.core.CredentialAuthenticationMode
import com.trilogys.quotapulse.core.CredentialStore
import com.trilogys.quotapulse.core.ProviderErrorClassifier
import com.trilogys.quotapulse.core.ProviderErrorKind
import com.trilogys.quotapulse.core.ProviderId
import com.trilogys.quotapulse.core.UsageService
import com.trilogys.quotapulse.core.UsageSnapshot
import com.trilogys.quotapulse.core.UsageWindow
import com.trilogys.quotapulse.ui.DashboardThemeOption
import com.trilogys.quotapulse.ui.DashboardThemePreferences
import com.trilogys.quotapulse.ui.LocalDashboardPalette
import com.trilogys.quotapulse.ui.QuotaPulseTheme
import com.trilogys.quotapulse.widget.QuotaPulseWidget
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (
            Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
        setContent {
            val context = LocalContext.current
            var theme by remember { mutableStateOf(DashboardThemePreferences.load(context)) }
            QuotaPulseTheme(theme) {
                val credentialStore = remember { CredentialStore(this) }
                QuotaPulseScreen(
                    store = remember { AccountStore(this) },
                    credentials = credentialStore,
                    service = remember { UsageService(credentialStore) },
                    oauth = remember { OAuthManager(this) },
                    selectedTheme = theme,
                    onThemeChanged = {
                        theme = it
                        DashboardThemePreferences.save(context, it)
                    },
                    updateWidget = { QuotaPulseWidget().updateAll(this) }
                )
            }
        }
    }
}

private data class AccountEditorSeed(
    val nonce: Int = 0,
    val provider: ProviderId = ProviderId.CODEX,
    val name: String = "",
    val reauthAccountID: String? = null
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuotaPulseScreen(
    store: AccountStore,
    credentials: CredentialStore,
    service: UsageService,
    oauth: OAuthManager,
    selectedTheme: DashboardThemeOption,
    onThemeChanged: (DashboardThemeOption) -> Unit,
    updateWidget: suspend () -> Unit
) {
    val context = LocalContext.current
    val palette = LocalDashboardPalette.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var accounts by remember { mutableStateOf(store.accounts()) }
    var revision by remember { mutableIntStateOf(0) }
    var selectedProvider by remember { mutableStateOf<ProviderId?>(null) }
    var status by remember { mutableStateOf("") }
    var isRefreshing by remember { mutableStateOf(false) }
    var editorSeed by remember { mutableStateOf(AccountEditorSeed()) }
    var showingEditor by remember { mutableStateOf(false) }
    var showingSettings by remember { mutableStateOf(false) }

    fun reload() {
        accounts = store.accounts()
        revision += 1
    }

    suspend fun refreshOne(account: AccountRecord) {
        store.clearCooldown(account.id)
        runCatching { service.refresh(account) }
            .onSuccess {
                store.clearCooldown(account.id)
                store.saveSnapshot(it.copy(stale = false, errorMessage = null, errorKind = null))
            }
            .onFailure {
                store.markStale(account.id, it.message ?: context.getString(R.string.health_unknown))
            }
    }

    fun saveCredential(provider: ProviderId, name: String, credential: Credential) {
        val normalized = if (credential.authenticationMode != null) {
            credential
        } else {
            credential.copy(
                authenticationMode = if (
                    credential.refreshToken.isNullOrBlank() &&
                    credential.accountId.isNullOrBlank() &&
                    credential.clientId.isNullOrBlank()
                ) CredentialAuthenticationMode.API_KEY else CredentialAuthenticationMode.OAUTH
            )
        }
        val reauthID = editorSeed.reauthAccountID
        if (reauthID != null) {
            val account = accounts.firstOrNull { it.id == reauthID }
            if (account != null) {
                credentials.save(account.id, normalized)
                store.clearCooldown(account.id)
                showingEditor = false
                status = context.getString(R.string.reauth_success, account.name)
                scope.launch {
                    withContext(Dispatchers.IO) { refreshOne(account) }
                    updateWidget()
                    reload()
                }
                return
            }
        }
        val account = AccountRecord(provider = provider, name = name.ifBlank { provider.displayName() })
        store.upsert(account)
        credentials.save(account.id, normalized)
        showingEditor = false
        reload()
        scope.launch { updateWidget() }
    }

    fun openAddAccount() {
        editorSeed = AccountEditorSeed(nonce = editorSeed.nonce + 1)
        showingEditor = true
    }

    fun beginReauthentication(account: AccountRecord) {
        editorSeed = AccountEditorSeed(
            nonce = editorSeed.nonce + 1,
            provider = account.provider,
            name = account.name,
            reauthAccountID = account.id
        )
        showingEditor = true
    }

    val snapshots = remember(accounts, revision) {
        accounts.mapNotNull { account -> store.snapshot(account.id)?.let { account.id to it } }.toMap()
    }
    val filteredAccounts = selectedProvider?.let { provider ->
        accounts.filter { it.provider == provider }
    } ?: accounts
    val recommended = recommendedAccountIds(accounts, snapshots)
    val lastUpdated = snapshots.values.maxOfOrNull { it.updatedAtEpochSeconds }

    LaunchedEffect(status) {
        if (status.isNotBlank()) {
            snackbar.showSnackbar(status)
            status = ""
        }
    }

    Scaffold(
        containerColor = palette.background,
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(palette.background),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                DashboardHeader(
                    lastUpdated = lastUpdated,
                    onSettings = { showingSettings = true },
                    onAdd = ::openAddAccount
                )
            }
            item {
                ProviderFilterBar(
                    selectedProvider = selectedProvider,
                    onSelected = { selectedProvider = it }
                )
            }
            item {
                DashboardOverviewCard(
                    accounts = accounts,
                    snapshots = snapshots,
                    lastUpdated = lastUpdated
                )
            }
            item {
                AccountSectionHeader(
                    count = filteredAccounts.size,
                    onRefreshAll = {
                        if (!isRefreshing) {
                            scope.launch {
                                isRefreshing = true
                                try {
                                    withContext(Dispatchers.IO) {
                                        store.accounts().filter { it.enabled }.forEach { refreshOne(it) }
                                    }
                                    reload()
                                    updateWidget()
                                } finally {
                                    isRefreshing = false
                                }
                            }
                        }
                    }
                )
            }
            if (filteredAccounts.isEmpty()) {
                item { EmptyAccountCard(hasAccounts = accounts.isNotEmpty(), onAdd = ::openAddAccount) }
            } else {
                items(filteredAccounts, key = { it.id }) { account ->
                    val snapshot = snapshots[account.id]
                    AccountDashboardCard(
                        account = account,
                        snapshot = snapshot,
                        recommended = recommended.contains(account.id),
                        credentialStatus = stringResource(
                            credentialHealthRes(account, credentials, snapshot?.stale == true)
                        ),
                        health = providerHealthText(context, snapshot, store.cooldownUntil(account.id)),
                        onRefresh = {
                            scope.launch {
                                withContext(Dispatchers.IO) { refreshOne(account) }
                                reload()
                                updateWidget()
                            }
                        },
                        onReauthenticate = { beginReauthentication(account) },
                        onToggle = {
                            store.setEnabled(account.id, !account.enabled)
                            reload()
                            scope.launch { updateWidget() }
                        },
                        onMoveUp = {
                            store.move(account.id, -1)
                            reload()
                            scope.launch { updateWidget() }
                        },
                        onMoveDown = {
                            store.move(account.id, 1)
                            reload()
                            scope.launch { updateWidget() }
                        },
                        onDelete = {
                            store.delete(account.id)
                            credentials.delete(account.id)
                            reload()
                            scope.launch { updateWidget() }
                        }
                    )
                }
            }
            item { Spacer(Modifier.height(8.dp)) }
        }
    }

    if (showingEditor) {
        key(editorSeed.nonce) {
            AccountEditorSheet(
                seed = editorSeed,
                oauth = oauth,
                onDismiss = { showingEditor = false },
                onStatus = { status = it },
                onCredential = ::saveCredential
            )
        }
    }

    if (showingSettings) {
        SettingsSheet(
            selectedTheme = selectedTheme,
            onThemeChanged = onThemeChanged,
            onDismiss = { showingSettings = false },
            onConfigChanged = {
                reload()
                updateWidget()
            }
        )
    }
}

@Composable
private fun DashboardHeader(
    lastUpdated: Long?,
    onSettings: () -> Unit,
    onAdd: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = stringResource(R.string.app_name),
                color = palette.secondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.overview_title),
                color = palette.primaryText,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
            Text(
                text = lastUpdated?.let {
                    stringResource(R.string.last_refreshed, formatTime(it))
                } ?: stringResource(R.string.never_refreshed),
                color = palette.secondaryText,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
        }
        LivePill()
        Spacer(Modifier.width(8.dp))
        DashboardIconButton(
            icon = { Icon(Icons.Rounded.Settings, contentDescription = stringResource(R.string.settings)) },
            onClick = onSettings
        )
        Spacer(Modifier.width(8.dp))
        DashboardIconButton(
            primary = true,
            icon = { Icon(Icons.Rounded.Add, contentDescription = stringResource(R.string.add_account)) },
            onClick = onAdd
        )
    }
}

@Composable
private fun LivePill() {
    val palette = LocalDashboardPalette.current
    Row(
        modifier = Modifier
            .background(palette.success.copy(alpha = 0.12f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(color = palette.success, shape = CircleShape, modifier = Modifier.size(6.dp)) {}
        Text("LIVE", color = palette.success, fontSize = 10.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun DashboardIconButton(
    primary: Boolean = false,
    icon: @Composable () -> Unit,
    onClick: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    Surface(
        onClick = onClick,
        modifier = Modifier.size(38.dp),
        shape = CircleShape,
        color = if (primary) palette.primary else palette.surfaceRaised,
        contentColor = if (primary) Color.White else palette.primaryText,
        border = if (primary) null else BorderStroke(1.dp, palette.border)
    ) {
        Box(contentAlignment = Alignment.Center) { icon() }
    }
}

@Composable
private fun ProviderFilterBar(
    selectedProvider: ProviderId?,
    onSelected: (ProviderId?) -> Unit
) {
    val palette = LocalDashboardPalette.current
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            ProviderFilterChip(
                title = stringResource(R.string.all),
                color = palette.primary,
                selected = selectedProvider == null,
                onClick = { onSelected(null) }
            )
        }
        items(ProviderId.entries) { provider ->
            ProviderFilterChip(
                title = provider.displayName(),
                color = palette.accent(provider),
                selected = selectedProvider == provider,
                onClick = { onSelected(provider) }
            )
        }
    }
}

@Composable
private fun ProviderFilterChip(
    title: String,
    color: Color,
    selected: Boolean,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    FilterChip(
        selected = selected,
        enabled = enabled,
        onClick = onClick,
        label = { Text(title, fontWeight = FontWeight.SemiBold) },
        colors = FilterChipDefaults.filterChipColors(
            containerColor = palette.surface,
            labelColor = palette.secondaryText,
            selectedContainerColor = color.copy(alpha = 0.82f),
            selectedLabelColor = Color.White
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = palette.border,
            selectedBorderColor = color
        ),
        shape = CircleShape
    )
}

@Composable
private fun DashboardOverviewCard(
    accounts: List<AccountRecord>,
    snapshots: Map<String, UsageSnapshot>,
    lastUpdated: Long?
) {
    val palette = LocalDashboardPalette.current
    val enabled = accounts.filter { it.enabled }
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(palette.cardCornerRadius.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (enabled.isEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Rounded.AccountCircle,
                        contentDescription = null,
                        tint = palette.secondaryText,
                        modifier = Modifier.size(42.dp)
                    )
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(
                            stringResource(R.string.no_active_accounts),
                            color = palette.primaryText,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            stringResource(R.string.add_account_hint),
                            color = palette.secondaryText,
                            fontSize = 11.sp
                        )
                    }
                }
            } else {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    items(enabled, key = { it.id }) { account ->
                        AccountOverviewRing(account, snapshots[account.id])
                    }
                }
            }
            HorizontalDivider(color = palette.border)
            Row(modifier = Modifier.fillMaxWidth()) {
                OverviewMetric(
                    value = enabled.size.toString(),
                    label = stringResource(R.string.active_accounts),
                    modifier = Modifier.weight(1f)
                )
                OverviewMetric(
                    value = enabled.map { it.provider }.distinct().size.toString(),
                    label = stringResource(R.string.providers),
                    modifier = Modifier.weight(1f)
                )
                OverviewMetric(
                    value = lastUpdated?.let(::formatTime) ?: "--",
                    label = stringResource(R.string.latest_update),
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun AccountOverviewRing(account: AccountRecord, snapshot: UsageSnapshot?) {
    val palette = LocalDashboardPalette.current
    val quotaColor = if (snapshot?.balance?.available == false) MaterialTheme.colorScheme.error else palette.success
    val progress = snapshot?.windows?.minOfOrNull { it.remainingPercent }
        ?.div(100.0)?.coerceIn(0.0, 1.0)?.toFloat()
        ?: if (snapshot?.balance?.available == true) 1f else 0f
    val value = snapshot?.balance?.let { "${it.symbol}${"%.2f".format(it.total)}" }
        ?: snapshot?.windows?.minOfOrNull { it.remainingPercent }
            ?.let { "${it.roundToInt()}%" }
        ?: "--"
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(modifier = Modifier.size(76.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxSize(),
                color = quotaColor,
                trackColor = palette.surfaceRaised,
                strokeWidth = 7.dp
            )
            Text(
                value,
                color = if (snapshot == null) palette.secondaryText else quotaColor,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }
        Spacer(Modifier.height(7.dp))
        Text(
            account.name,
            modifier = Modifier.widthIn(max = 92.dp),
            color = palette.secondaryText,
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun OverviewMetric(value: String, label: String, modifier: Modifier = Modifier) {
    val palette = LocalDashboardPalette.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, color = palette.primaryText, fontSize = 15.sp, fontWeight = FontWeight.Bold)
        Text(label, color = palette.secondaryText, fontSize = 9.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun AccountSectionHeader(
    count: Int,
    onRefreshAll: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            stringResource(R.string.account_quota),
            color = palette.primaryText,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.width(8.dp))
        Text(
            count.toString(),
            modifier = Modifier
                .background(palette.surfaceRaised, CircleShape)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            color = palette.secondaryText,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onRefreshAll) {
            Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.refresh_all), fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun EmptyAccountCard(hasAccounts: Boolean, onAdd: () -> Unit) {
    val palette = LocalDashboardPalette.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(palette.cardCornerRadius.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 28.dp, horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                if (hasAccounts) stringResource(R.string.no_filtered_accounts)
                else stringResource(R.string.no_accounts),
                color = palette.primaryText,
                fontWeight = FontWeight.Bold
            )
            if (!hasAccounts) {
                Button(onClick = onAdd) {
                    Icon(Icons.Rounded.Add, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.add_account))
                }
            }
        }
    }
}

@Composable
private fun AccountDashboardCard(
    account: AccountRecord,
    snapshot: UsageSnapshot?,
    recommended: Boolean,
    credentialStatus: String,
    health: String?,
    onRefresh: () -> Unit,
    onReauthenticate: () -> Unit,
    onToggle: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    val accent = palette.accent(account.provider)
    var menuExpanded by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (account.enabled) 1f else 0.62f),
        shape = RoundedCornerShape(palette.cardCornerRadius.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surface),
        border = BorderStroke(1.dp, palette.border)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(color = accent, shape = CircleShape, modifier = Modifier.size(10.dp)) {}
                Spacer(Modifier.width(9.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "${account.provider.displayName()} · ${account.name}",
                        color = palette.primaryText,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        credentialStatus,
                        color = palette.secondaryText,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
                if (recommended) {
                    StatusPill(stringResource(R.string.recommended), accent)
                    Spacer(Modifier.width(6.dp))
                }
                if (!account.enabled) {
                    StatusPill(stringResource(R.string.hidden), palette.warning)
                }
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.account_actions))
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(if (account.enabled) R.string.hide else R.string.show)) },
                            leadingIcon = {
                                Icon(
                                    if (account.enabled) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                                    contentDescription = null
                                )
                            },
                            onClick = { menuExpanded = false; onToggle() }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.move_up)) },
                            leadingIcon = { Icon(Icons.Rounded.ArrowUpward, contentDescription = null) },
                            onClick = { menuExpanded = false; onMoveUp() }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.move_down)) },
                            leadingIcon = { Icon(Icons.Rounded.ArrowDownward, contentDescription = null) },
                            onClick = { menuExpanded = false; onMoveDown() }
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                            leadingIcon = {
                                Icon(
                                    Icons.Rounded.Delete,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error
                                )
                            },
                            onClick = { menuExpanded = false; confirmDelete = true }
                        )
                    }
                }
            }

            health?.let {
                Text(it, color = palette.warning, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }

            snapshot?.balance?.let { BalanceDisplay(it) }
            snapshot?.windows?.take(3)?.forEach { window -> QuotaWindowDisplay(window) }

            if (
                snapshot == null ||
                (snapshot.balance == null && snapshot.windows.isEmpty() && snapshot.connectionLabel == null)
            ) {
                Text(stringResource(R.string.no_data), color = palette.secondaryText, fontSize = 12.sp)
            } else if (snapshot.balance == null && snapshot.windows.isEmpty()) {
                snapshot.connectionLabel?.let {
                    Text(it, color = palette.primaryText, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            snapshot?.availableModels?.takeIf { it.isNotEmpty() }?.let { models ->
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            stringResource(R.string.available_models),
                            color = accent,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            models.size.toString(),
                            color = palette.secondaryText,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        items(models, key = { it }) { model ->
                            Text(
                                model,
                                modifier = Modifier
                                    .background(
                                        palette.surfaceRaised,
                                        RoundedCornerShape(palette.compactCornerRadius.dp)
                                    )
                                    .padding(horizontal = 9.dp, vertical = 6.dp),
                                color = palette.primaryText,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1
                            )
                        }
                    }
                }
            }

            HorizontalDivider(color = palette.border)
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onRefresh) {
                    Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(17.dp))
                    Spacer(Modifier.width(5.dp))
                    Text(stringResource(R.string.refresh), fontWeight = FontWeight.SemiBold)
                }
                TextButton(onClick = onReauthenticate) {
                    Icon(Icons.Rounded.Key, contentDescription = null, modifier = Modifier.size(17.dp))
                    Spacer(Modifier.width(5.dp))
                    Text(stringResource(R.string.reauthenticate), fontWeight = FontWeight.SemiBold)
                }
            }
            snapshot?.let {
                Text(
                    stringResource(R.string.updated, formatTime(it.updatedAtEpochSeconds)),
                    modifier = Modifier.align(Alignment.End),
                    color = palette.secondaryText,
                    fontSize = 9.sp,
                    maxLines = 1
                )
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_account_title)) },
            text = { Text(stringResource(R.string.delete_account_message, account.name)) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; onDelete() }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

@Composable
private fun StatusPill(text: String, color: Color) {
    Text(
        text,
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 5.dp),
        color = color,
        fontSize = 9.sp,
        fontWeight = FontWeight.Bold,
        maxLines = 1
    )
}

@Composable
private fun BalanceDisplay(balance: BalanceSnapshot) {
    val palette = LocalDashboardPalette.current
    Row(verticalAlignment = Alignment.Bottom) {
        Text(
            stringResource(R.string.available_balance),
            modifier = Modifier.weight(1f),
            color = palette.secondaryText,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium
        )
        Text(
            "${balance.symbol}${"%.2f".format(balance.total)}",
            color = if (balance.available) palette.success else MaterialTheme.colorScheme.error,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun QuotaWindowDisplay(window: UsageWindow) {
    val palette = LocalDashboardPalette.current
    val quotaColor = palette.success
    val remaining = window.remainingPercent.coerceIn(0.0, 100.0)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(window.label, color = palette.primaryText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(
                "${remaining.roundToInt()}%",
                color = quotaColor,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
            window.resetAtEpochSeconds?.let {
                Spacer(Modifier.width(7.dp))
                Text(
                    stringResource(R.string.reset_in, formatCountdown(it)),
                    color = palette.secondaryText,
                    fontSize = 9.sp
                )
            }
        }
        LinearProgressIndicator(
            progress = { (remaining / 100.0).toFloat() },
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp),
            color = quotaColor,
            trackColor = palette.surfaceRaised
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountEditorSheet(
    seed: AccountEditorSeed,
    oauth: OAuthManager,
    onDismiss: () -> Unit,
    onStatus: (String) -> Unit,
    onCredential: (ProviderId, String, Credential) -> Unit
) {
    val context = LocalContext.current
    val palette = LocalDashboardPalette.current
    val scope = rememberCoroutineScope()
    var provider by remember { mutableStateOf(seed.provider) }
    var name by remember { mutableStateOf(seed.name) }
    var accessToken by remember { mutableStateOf("") }
    var refreshToken by remember { mutableStateOf("") }
    var accountID by remember { mutableStateOf("") }
    var baseURL by remember { mutableStateOf("") }
    var callbackValue by remember { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = palette.background,
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(13.dp)
        ) {
            SheetHeader(
                title = if (seed.reauthAccountID == null) {
                    stringResource(R.string.add_account)
                } else {
                    stringResource(R.string.reauthenticate)
                },
                onDismiss = onDismiss
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(ProviderId.entries) { item ->
                    ProviderFilterChip(
                        title = item.displayName(),
                        color = palette.accent(item),
                        selected = provider == item,
                        enabled = seed.reauthAccountID == null,
                        onClick = {
                            provider = item
                            callbackValue = ""
                        }
                    )
                }
            }
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.account_name_optional)) },
                singleLine = true,
                shape = RoundedCornerShape(palette.compactCornerRadius.dp)
            )

            if (provider in setOf(ProviderId.CODEX, ProviderId.CLAUDE, ProviderId.KIMI)) {
                Text(
                    stringResource(R.string.oauth_sign_in),
                    color = palette.primaryText,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold
                )
                when (provider) {
                    ProviderId.CODEX -> {
                        Button(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                onStatus(context.getString(R.string.codex_open_browser))
                                scope.launch {
                                    runCatching { oauth.loginCodex() }
                                        .onSuccess { onCredential(ProviderId.CODEX, name, it) }
                                        .onFailure {
                                            onStatus(context.getString(R.string.codex_manual_fallback, it.message ?: "OAuth failed"))
                                        }
                                }
                            }
                        ) {
                            Text(stringResource(if (seed.reauthAccountID == null) R.string.codex_login else R.string.codex_relogin))
                        }
                        OutlinedButton(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                oauth.copyCodexAuthorizationLink()
                                onStatus(context.getString(R.string.codex_link_copied))
                            }
                        ) {
                            Icon(Icons.Rounded.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.copy_authorization_link))
                        }
                        OutlinedTextField(
                            value = callbackValue,
                            onValueChange = { callbackValue = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.codex_callback_hint)) },
                            shape = RoundedCornerShape(palette.compactCornerRadius.dp)
                        )
                        OutlinedButton(
                            enabled = callbackValue.isNotBlank(),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                scope.launch {
                                    runCatching { oauth.completeCodexManual(callbackValue) }
                                        .onSuccess { onCredential(ProviderId.CODEX, name, it) }
                                        .onFailure { onStatus(it.message ?: "Codex callback failed") }
                                }
                            }
                        ) { Text(stringResource(R.string.codex_callback)) }
                    }
                    ProviderId.CLAUDE -> {
                        Button(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                oauth.beginClaude()
                                onStatus(context.getString(R.string.claude_paste_code))
                            }
                        ) {
                            Text(stringResource(if (seed.reauthAccountID == null) R.string.claude_login else R.string.claude_relogin))
                        }
                        OutlinedButton(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                oauth.copyClaudeAuthorizationLink()
                                onStatus(context.getString(R.string.claude_link_copied))
                            }
                        ) {
                            Icon(Icons.Rounded.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.copy_authorization_link))
                        }
                        OutlinedTextField(
                            value = callbackValue,
                            onValueChange = { callbackValue = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.claude_code_hint)) },
                            shape = RoundedCornerShape(palette.compactCornerRadius.dp)
                        )
                        OutlinedButton(
                            enabled = callbackValue.isNotBlank(),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                scope.launch {
                                    runCatching { oauth.completeClaude(callbackValue) }
                                        .onSuccess { onCredential(ProviderId.CLAUDE, name, it) }
                                        .onFailure { onStatus(it.message ?: "Claude OAuth failed") }
                                }
                            }
                        ) { Text(stringResource(R.string.claude_complete)) }
                    }
                    ProviderId.KIMI -> {
                        Button(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                onStatus(context.getString(R.string.kimi_starting))
                                scope.launch {
                                    runCatching { oauth.loginKimi() }
                                        .onSuccess { onCredential(ProviderId.KIMI, name, it) }
                                        .onFailure { onStatus(it.message ?: "Kimi OAuth failed") }
                                }
                            }
                        ) {
                            Text(stringResource(if (seed.reauthAccountID == null) R.string.kimi_login else R.string.kimi_relogin))
                        }
                        OutlinedButton(
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                scope.launch {
                                    runCatching {
                                        oauth.loginKimi(copyAuthorizationLink = true) { userCode ->
                                            onStatus(
                                                if (userCode == null) {
                                                    context.getString(R.string.kimi_link_copied)
                                                } else {
                                                    context.getString(R.string.kimi_link_copied_with_code, userCode)
                                                }
                                            )
                                        }
                                    }
                                        .onSuccess { onCredential(ProviderId.KIMI, name, it) }
                                        .onFailure { onStatus(it.message ?: "Kimi OAuth failed") }
                                }
                            }
                        ) {
                            Icon(Icons.Rounded.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.copy_authorization_link))
                        }
                    }
                    else -> Unit
                }
                HorizontalDivider(color = palette.border)
            }

            Text(
                stringResource(R.string.api_credentials),
                color = palette.primaryText,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
            )
            OutlinedTextField(
                value = accessToken,
                onValueChange = { accessToken = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.access_token)) },
                singleLine = true,
                shape = RoundedCornerShape(palette.compactCornerRadius.dp)
            )
            if (!isApiKeyProvider(provider)) {
                OutlinedTextField(
                    value = refreshToken,
                    onValueChange = { refreshToken = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.refresh_token)) },
                    singleLine = true,
                    shape = RoundedCornerShape(palette.compactCornerRadius.dp)
                )
            }
            if (provider == ProviderId.CODEX) {
                OutlinedTextField(
                    value = accountID,
                    onValueChange = { accountID = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.account_id_optional)) },
                    singleLine = true,
                    shape = RoundedCornerShape(palette.compactCornerRadius.dp)
                )
            }
            OutlinedTextField(
                value = baseURL,
                onValueChange = { baseURL = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.base_url_optional)) },
                singleLine = true,
                shape = RoundedCornerShape(palette.compactCornerRadius.dp)
            )
            Button(
                enabled = accessToken.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    onCredential(
                        provider,
                        name,
                        Credential(
                            accessToken = accessToken.trim(),
                            refreshToken = refreshToken.trim().ifBlank { null },
                            accountId = accountID.trim().ifBlank { null },
                            baseUrl = baseURL.trim().ifBlank { null }
                        )
                    )
                }
            ) {
                Icon(Icons.Rounded.Key, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(if (seed.reauthAccountID == null) R.string.import_credentials else R.string.update_credentials))
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSheet(
    selectedTheme: DashboardThemeOption,
    onThemeChanged: (DashboardThemeOption) -> Unit,
    onDismiss: () -> Unit,
    onConfigChanged: suspend () -> Unit
) {
    val palette = LocalDashboardPalette.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = palette.background,
        dragHandle = null
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            SheetHeader(stringResource(R.string.settings), onDismiss)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Palette, contentDescription = null, tint = palette.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.appearance),
                    color = palette.primaryText,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            DashboardThemeOption.entries.forEach { option ->
                ThemeOptionRow(
                    option = option,
                    selected = option == selectedTheme,
                    onClick = { onThemeChanged(option) }
                )
            }
            HorizontalDivider(color = palette.border)
            PortableConfigSection(onChanged = onConfigChanged)
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ThemeOptionRow(
    option: DashboardThemeOption,
    selected: Boolean,
    onClick: () -> Unit
) {
    val palette = LocalDashboardPalette.current
    val (title, subtitle) = when (option) {
        DashboardThemeOption.DAYLIGHT -> stringResource(R.string.theme_daylight) to stringResource(R.string.theme_daylight_subtitle)
        DashboardThemeOption.NEON -> stringResource(R.string.theme_neon) to stringResource(R.string.theme_neon_subtitle)
        DashboardThemeOption.GRAPHITE -> stringResource(R.string.theme_graphite) to stringResource(R.string.theme_graphite_subtitle)
        DashboardThemeOption.AURORA -> stringResource(R.string.theme_aurora) to stringResource(R.string.theme_aurora_subtitle)
    }
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(palette.compactCornerRadius.dp),
        color = palette.surface,
        border = BorderStroke(if (selected) 2.dp else 1.dp, if (selected) palette.primary else palette.border)
    ) {
        Row(
            modifier = Modifier.padding(13.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ThemeSwatch(option)
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, color = palette.primaryText, fontWeight = FontWeight.Bold)
                Text(subtitle, color = palette.secondaryText, fontSize = 10.sp)
            }
            if (selected) {
                Icon(Icons.Rounded.Check, contentDescription = null, tint = palette.primary)
            }
        }
    }
}

@Composable
private fun ThemeSwatch(option: DashboardThemeOption) {
    val colors = when (option) {
        DashboardThemeOption.DAYLIGHT -> listOf(Color(0xFFED571A), Color(0xFFF51A47), Color(0xFF29A657))
        DashboardThemeOption.NEON -> listOf(Color(0xFF7D33F5), Color(0xFF40D1CC), Color(0xFF33C773))
        DashboardThemeOption.GRAPHITE -> listOf(Color(0xFF33C299), Color(0xFFF28730), Color(0xFF54BD70))
        DashboardThemeOption.AURORA -> listOf(Color(0xFF38D1CC), Color(0xFF9E57F0), Color(0xFF33C773))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        colors.forEach { color -> Surface(color = color, shape = CircleShape, modifier = Modifier.size(10.dp)) {} }
    }
}

@Composable
private fun SheetHeader(title: String, onDismiss: () -> Unit) {
    val palette = LocalDashboardPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            title,
            modifier = Modifier.weight(1f),
            color = palette.primaryText,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold
        )
        IconButton(onClick = onDismiss) {
            Icon(Icons.Rounded.Close, contentDescription = stringResource(R.string.close))
        }
    }
}

private fun ProviderId.displayName(): String = when (this) {
    ProviderId.CODEX -> "Codex"
    ProviderId.CLAUDE -> "Claude"
    ProviderId.KIMI -> "Kimi"
    ProviderId.DEEPSEEK -> "DeepSeek"
    ProviderId.MINIMAX -> "MiniMax"
    ProviderId.GLM -> "GLM"
    ProviderId.COPILOT -> "Copilot"
}

private fun isApiKeyProvider(provider: ProviderId): Boolean = provider in setOf(
    ProviderId.DEEPSEEK,
    ProviderId.MINIMAX,
    ProviderId.GLM,
    ProviderId.COPILOT
)

private fun providerHealthText(
    context: Context,
    snapshot: UsageSnapshot?,
    cooldown: Long?
): String? {
    snapshot ?: return null
    val kind = snapshot.errorKind
        ?: snapshot.errorMessage?.let(ProviderErrorClassifier::classify)
        ?: return null
    val label = context.getString(
        when (kind) {
            ProviderErrorKind.AUTHENTICATION -> R.string.health_authentication
            ProviderErrorKind.RATE_LIMITED -> R.string.health_rate_limited
            ProviderErrorKind.PROVIDER_UNAVAILABLE -> R.string.health_provider_unavailable
            ProviderErrorKind.NETWORK -> R.string.health_network
            ProviderErrorKind.INVALID_RESPONSE -> R.string.health_invalid_response
            ProviderErrorKind.CONFIGURATION -> R.string.health_configuration
            ProviderErrorKind.UNKNOWN -> R.string.health_unknown
        }
    )
    val cached = snapshot.stale && (snapshot.windows.isNotEmpty() || snapshot.balance != null)
    val base = if (cached) context.getString(R.string.health_cached, label) else label
    val retry = cooldown?.let { " · ${context.getString(R.string.health_retry_in, formatCountdown(it))}" }.orEmpty()
    return "$base$retry"
}

@StringRes
private fun credentialHealthRes(
    account: AccountRecord,
    store: CredentialStore,
    stale: Boolean
): Int {
    val credential = store.get(account.id) ?: return R.string.credential_sign_in_again
    if (isApiKeyProvider(account.provider) || credential.authenticationMode == CredentialAuthenticationMode.API_KEY) {
        return if (stale) R.string.credential_cached else R.string.credential_healthy
    }
    credential.expiresAtEpochSeconds?.let { expiresAt ->
        val now = System.currentTimeMillis() / 1000
        if (expiresAt <= now) {
            return if (!credential.refreshToken.isNullOrBlank()) {
                R.string.credential_refreshable
            } else {
                R.string.credential_sign_in_again
            }
        }
        if (expiresAt - now < 3600) return R.string.credential_renew_soon
    }
    return if (stale) R.string.credential_cached else R.string.credential_healthy
}

private fun recommendedAccountIds(
    accounts: List<AccountRecord>,
    snapshots: Map<String, UsageSnapshot>
): Set<String> = ProviderId.entries.mapNotNull { provider ->
    accounts.asSequence()
        .filter { it.enabled && it.provider == provider }
        .mapNotNull { account ->
            val snapshot = snapshots[account.id]?.takeUnless { it.stale } ?: return@mapNotNull null
            val score = snapshot.balance?.total
                ?: snapshot.windows.minOfOrNull { it.remainingPercent }
                ?: return@mapNotNull null
            account.id to score
        }
        .maxByOrNull { it.second }
        ?.first
}.toSet()

private fun formatCountdown(epoch: Long): String {
    val remaining = (epoch - System.currentTimeMillis() / 1000).coerceAtLeast(0)
    val days = remaining / 86_400
    val hours = (remaining % 86_400) / 3_600
    val minutes = (remaining % 3_600) / 60
    return when {
        days > 0 -> "${days}d ${hours}h"
        hours > 0 -> "${hours}h ${minutes}m"
        else -> "${minutes.coerceAtLeast(1)}m"
    }
}

private fun formatTime(epoch: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT)
    .format(Date(epoch * 1000))
