package com.trilogys.aiquota

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.trilogys.aiquota.core.PortableConfigManager
import com.trilogys.aiquota.core.PortableImportMode

@Composable
fun PortableConfigSection(onChanged: suspend () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val manager = remember { PortableConfigManager(context) }
    var replace by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var pendingSensitiveExport by remember { mutableStateOf(false) }
    var pendingExport by remember { mutableStateOf<String?>(null) }

    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching { context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } ?: error("Cannot read configuration") }
            .onSuccess { raw -> runCatching { manager.import(raw, if (replace) PortableImportMode.REPLACE else PortableImportMode.MERGE) }
                .onSuccess { r -> status = "导入完成：新增 ${r.added}，更新 ${r.updated}，凭据 ${r.credentialsImported}"; scope.launch { onChanged() } }
                .onFailure { status = "导入失败：${it.message}" } }
            .onFailure { status = "读取失败：${it.message}" }
    }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val raw = pendingExport; pendingExport = null
        if (uri != null && raw != null) runCatching { writeText(context, uri, raw) }.onSuccess { status = "配置已导出" }.onFailure { status = "导出失败：${it.message}" }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("导入与导出", style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Switch(checked = replace, onCheckedChange = { replace = it }); Text(if (replace) "替换现有账号" else "合并导入") }
        Button(onClick = { importLauncher.launch(arrayOf("application/json", "text/json", "application/octet-stream")) }) { Text("导入 AI Quota 配置") }
        Button(onClick = { pendingExport = manager.export(false); exportLauncher.launch("ai-quota-native.json") }) { Text("导出配置（不含凭据）") }
        Button(onClick = { pendingSensitiveExport = true }) { Text("完整备份（含 Token / API Key）") }
        Text("完整备份可用于 iOS 与 Android 之间迁移登录状态。文件包含敏感凭据，请只保存到可信位置。", style = MaterialTheme.typography.bodySmall)
        if (status.isNotBlank()) Text(status)
    }

    if (pendingSensitiveExport) AlertDialog(
        onDismissRequest = { pendingSensitiveExport = false },
        title = { Text("完整备份包含敏感凭据") },
        text = { Text("任何获得此文件的人都可能取得其中的 API Key、Access Token 或 Refresh Token。不要上传到公开网盘、聊天群或 GitHub。") },
        confirmButton = { TextButton(onClick = { pendingSensitiveExport = false; pendingExport = manager.export(true); exportLauncher.launch("ai-quota-native-full.json") }) { Text("继续导出") } },
        dismissButton = { TextButton(onClick = { pendingSensitiveExport = false }) { Text("取消") } }
    )
}

private fun writeText(context: Context, uri: Uri, value: String) {
    context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter()?.use { it.write(value) } ?: error("Cannot write configuration")
}
