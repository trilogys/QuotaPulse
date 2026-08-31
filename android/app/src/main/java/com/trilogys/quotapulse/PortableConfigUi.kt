package com.trilogys.quotapulse

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.trilogys.quotapulse.core.PortableConfigManager
import com.trilogys.quotapulse.core.PortableImportMode
import com.trilogys.quotapulse.ui.LocalDashboardPalette
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

@Composable
fun PortableConfigSection(onChanged: suspend () -> Unit) {
    val context = LocalContext.current
    val palette = LocalDashboardPalette.current
    val scope = rememberCoroutineScope()
    val manager = remember { PortableConfigManager(context) }
    var replace by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var pendingSensitiveExport by remember { mutableStateOf(false) }
    var pendingExport by remember { mutableStateOf<String?>(null) }

    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: error(context.getString(R.string.config_read_failed, "Empty file"))
        }.onSuccess { raw ->
            runCatching {
                manager.import(raw, if (replace) PortableImportMode.REPLACE else PortableImportMode.MERGE)
            }.onSuccess { result ->
                status = context.getString(
                    R.string.config_import_complete,
                    result.added,
                    result.updated,
                    result.credentialsImported
                )
                scope.launch { onChanged() }
            }.onFailure {
                status = context.getString(R.string.config_import_failed, it.message.orEmpty())
            }
        }.onFailure {
            status = context.getString(R.string.config_read_failed, it.message.orEmpty())
        }
    }
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        val raw = pendingExport
        pendingExport = null
        if (uri != null && raw != null) {
            runCatching { writeText(context, uri, raw) }
                .onSuccess { status = context.getString(R.string.config_export_complete) }
                .onFailure {
                    status = context.getString(R.string.config_export_failed, it.message.orEmpty())
                }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            stringResource(R.string.config_transfer),
            color = palette.primaryText,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(checked = replace, onCheckedChange = { replace = it })
            Spacer(Modifier.width(9.dp))
            Text(
                stringResource(if (replace) R.string.config_replace else R.string.config_merge),
                color = palette.secondaryText,
                fontSize = 11.sp
            )
        }
        OutlinedButton(
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                importLauncher.launch(
                    arrayOf("application/json", "text/json", "application/octet-stream")
                )
            }
        ) {
            Icon(Icons.Rounded.FileDownload, contentDescription = null)
            Spacer(Modifier.width(7.dp))
            Text(stringResource(R.string.config_import))
        }
        OutlinedButton(
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                pendingExport = manager.export(false)
                exportLauncher.launch(exportFilename())
            }
        ) {
            Icon(Icons.Rounded.FileUpload, contentDescription = null)
            Spacer(Modifier.width(7.dp))
            Text(stringResource(R.string.config_export_without_credentials))
        }
        Button(
            modifier = Modifier.fillMaxWidth(),
            onClick = { pendingSensitiveExport = true }
        ) {
            Icon(Icons.Rounded.Lock, contentDescription = null)
            Spacer(Modifier.width(7.dp))
            Text(stringResource(R.string.config_full_backup))
        }
        Surface(
            color = palette.surfaceRaised,
            shape = RoundedCornerShape(palette.compactCornerRadius.dp)
        ) {
            Text(
                stringResource(R.string.config_backup_help),
                modifier = Modifier.padding(12.dp),
                color = palette.secondaryText,
                fontSize = 10.sp
            )
        }
        if (status.isNotBlank()) {
            Text(status, color = palette.secondaryText, fontSize = 11.sp)
        }
    }

    if (pendingSensitiveExport) {
        AlertDialog(
            onDismissRequest = { pendingSensitiveExport = false },
            title = { Text(stringResource(R.string.config_sensitive_title)) },
            text = { Text(stringResource(R.string.config_sensitive_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingSensitiveExport = false
                        pendingExport = manager.export(true)
                        exportLauncher.launch(exportFilename())
                    }
                ) { Text(stringResource(R.string.config_continue_export)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingSensitiveExport = false }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }
}

private fun exportFilename(): String = "QuotaPulse-backup-${
    LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"))
}.json"

private fun writeText(context: Context, uri: Uri, value: String) {
    context.contentResolver.openOutputStream(uri, "wt")
        ?.bufferedWriter()
        ?.use { it.write(value) }
        ?: error("Cannot write configuration")
}
