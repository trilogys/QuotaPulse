package com.trilogys.aiquota.core

import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import kotlin.math.max

class UsageService(
    private val credentialStore: CredentialStore,
    private val client: OkHttpClient = OkHttpClient()
) {
    fun refresh(account: AccountRecord): UsageSnapshot {
        val credential = credentialStore.get(account.id) ?: error("Missing credential")
        return when (account.provider) {
            ProviderId.CODEX -> fetchCodex(account, credential)
            ProviderId.CLAUDE -> fetchClaude(account, credential)
            ProviderId.KIMI -> fetchKimi(account, credential)
            ProviderId.DEEPSEEK -> fetchDeepSeek(account, credential)
        }
    }

    private fun execute(request: Request): Pair<Int, String> = client.newCall(request).execute().use {
        it.code to it.body?.string().orEmpty()
    }

    private fun fetchCodex(account: AccountRecord, initial: Credential): UsageSnapshot {
        var credential = initial
        fun call(c: Credential): Pair<Int, String> {
            val request = Request.Builder()
                .url("https://chatgpt.com/backend-api/wham/usage")
                .header("Authorization", "Bearer ${c.accessToken}")
                .header("User-Agent", "codex-cli")
                .header("Accept", "application/json")
                .apply { c.accountId?.takeIf(String::isNotBlank)?.let { header("chatgpt-account-id", it) } }
                .build()
            return execute(request)
        }
        var (code, body) = call(credential)
        if (code == 401 && !credential.refreshToken.isNullOrBlank()) {
            credential = refreshCodex(account.id, credential)
            val retry = call(credential); code = retry.first; body = retry.second
        }
        if (code !in 200..299) throw IOException("Codex HTTP $code: $body")
        val rateLimit = JSONObject(body).optJSONObject("rate_limit") ?: error("Missing rate_limit")
        val windows = buildList {
            val keys = rateLimit.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (!key.endsWith("_window")) continue
                val raw = rateLimit.optJSONObject(key) ?: continue
                if (!raw.has("used_percent")) continue
                val duration = raw.optLong("limit_window_seconds", 0L)
                val reset = when {
                    raw.optLong("reset_at", 0L) > 0 -> raw.optLong("reset_at")
                    raw.optLong("reset_after_seconds", -1L) >= 0 -> System.currentTimeMillis() / 1000 + raw.optLong("reset_after_seconds")
                    else -> null
                }
                add(UsageWindow("codex-$key", durationLabel(duration), 100.0 - raw.optDouble("used_percent"), reset))
            }
        }.distinctBy { it.label }
        if (windows.isEmpty()) error("No Codex quota windows")
        return UsageSnapshot(account.id, ProviderId.CODEX, windows = windows)
    }

    private fun refreshCodex(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val form = FormBody.Builder()
            .add("grant_type", "refresh_token")
            .add("refresh_token", refresh)
            .add("client_id", credential.clientId ?: CODEX_CLIENT_ID)
            .build()
        val (code, body) = execute(Request.Builder().url("https://auth.openai.com/oauth/token").post(form).header("Accept", "application/json").build())
        if (code !in 200..299) throw IOException("Codex refresh HTTP $code: $body")
        val json = JSONObject(body)
        val updated = credential.copy(
            accessToken = json.getString("access_token"),
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() } ?: refresh,
            idToken = json.optString("id_token").takeIf { it.isNotBlank() } ?: credential.idToken
        )
        credentialStore.save(accountId, updated)
        return updated
    }

    private fun fetchClaude(account: AccountRecord, initial: Credential): UsageSnapshot {
        var credential = initial
        if ((credential.expiresAtEpochSeconds ?: Long.MAX_VALUE) - nowEpoch() < 60 && !credential.refreshToken.isNullOrBlank()) {
            credential = refreshClaude(account.id, credential)
        }
        fun call(c: Credential) = execute(
            Request.Builder().url("https://api.anthropic.com/api/oauth/usage")
                .header("Authorization", "Bearer ${c.accessToken}")
                .header("anthropic-beta", "oauth-2025-04-20")
                .header("User-Agent", "claude-cli")
                .header("Accept", "application/json")
                .build()
        )
        var (code, body) = call(credential)
        if (code == 401 && !credential.refreshToken.isNullOrBlank()) {
            credential = refreshClaude(account.id, credential)
            val retry = call(credential); code = retry.first; body = retry.second
        }
        if (code !in 200..299) throw IOException("Claude HTTP $code: $body")
        val root = JSONObject(body)
        val windows = buildList {
            root.optJSONObject("five_hour")?.let { add(UsageWindow("claude-5h", "5h", 100 - it.optDouble("utilization"), parseIsoEpoch(it.optString("resets_at")))) }
            root.optJSONObject("seven_day")?.let { add(UsageWindow("claude-week", "周", 100 - it.optDouble("utilization"), parseIsoEpoch(it.optString("resets_at")))) }
        }
        if (windows.isEmpty()) error("No Claude quota windows")
        return UsageSnapshot(account.id, ProviderId.CLAUDE, windows = windows)
    }

    private fun refreshClaude(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val payload = JSONObject()
            .put("grant_type", "refresh_token")
            .put("refresh_token", refresh)
            .put("client_id", credential.clientId ?: CLAUDE_CLIENT_ID)
            .toString()
            .toRequestBody("application/json".toMediaType())
        val (code, body) = execute(Request.Builder().url("https://platform.claude.com/v1/oauth/token").post(payload).header("Accept", "application/json").build())
        if (code !in 200..299) throw IOException("Claude refresh HTTP $code: $body")
        val json = JSONObject(body)
        val updated = credential.copy(
            accessToken = json.getString("access_token"),
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() } ?: refresh,
            expiresAtEpochSeconds = json.optLong("expires_in").takeIf { it > 0 }?.let { nowEpoch() + it }
        )
        credentialStore.save(accountId, updated)
        return updated
    }

    private fun fetchKimi(account: AccountRecord, initial: Credential): UsageSnapshot {
        var credential = initial
        if ((credential.expiresAtEpochSeconds ?: Long.MAX_VALUE) - nowEpoch() < 60 && !credential.refreshToken.isNullOrBlank()) {
            credential = refreshKimi(account.id, credential)
        }
        fun call(c: Credential): Pair<Int, String> {
            val builder = Request.Builder().url("https://api.kimi.com/coding/v1/usages")
                .header("Authorization", "Bearer ${c.accessToken}").header("Accept", "application/json")
            c.deviceHeaders?.forEach { (k, v) -> builder.header(k, v) }
            return execute(builder.build())
        }
        var (code, body) = call(credential)
        if (code in listOf(401, 403) && !credential.refreshToken.isNullOrBlank()) {
            credential = refreshKimi(account.id, credential)
            val retry = call(credential); code = retry.first; body = retry.second
        }
        if (code !in 200..299) throw IOException("Kimi HTTP $code: $body")
        val root = JSONObject(body)
        val windows = mutableListOf<UsageWindow>()
        root.optJSONArray("limits")?.let { limits ->
            for (i in 0 until limits.length()) {
                val entry = limits.optJSONObject(i) ?: continue
                val window = entry.optJSONObject("window") ?: entry
                val detail = entry.optJSONObject("detail") ?: entry
                parseKimiDetail(detail, kimiDurationSeconds(window), "kimi-$i")?.let(windows::add)
            }
        }
        root.optJSONObject("usage")?.let { usage ->
            if (windows.none { it.label == "周" }) parseKimiDetail(usage, 604_800, "kimi-week-summary")?.let(windows::add)
        }
        val distinct = windows.distinctBy { it.label }
        if (distinct.isEmpty()) error("No Kimi quota windows")
        return UsageSnapshot(account.id, ProviderId.KIMI, windows = distinct)
    }

    private fun refreshKimi(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val form = FormBody.Builder()
            .add("client_id", credential.clientId ?: KIMI_CLIENT_ID)
            .add("grant_type", "refresh_token")
            .add("refresh_token", refresh)
            .build()
        val builder = Request.Builder().url("https://auth.kimi.com/api/oauth/token").post(form).header("Accept", "application/json")
        credential.deviceHeaders?.forEach { (k, v) -> builder.header(k, v) }
        val (code, body) = execute(builder.build())
        if (code !in 200..299) throw IOException("Kimi refresh HTTP $code: $body")
        val json = JSONObject(body)
        val updated = credential.copy(
            accessToken = json.getString("access_token"),
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() } ?: refresh,
            expiresAtEpochSeconds = json.optLong("expires_in").takeIf { it > 0 }?.let { nowEpoch() + it }
        )
        credentialStore.save(accountId, updated)
        return updated
    }

    private fun fetchDeepSeek(account: AccountRecord, credential: Credential): UsageSnapshot {
        val (code, body) = execute(
            Request.Builder().url("https://api.deepseek.com/user/balance")
                .header("Authorization", "Bearer ${credential.accessToken}")
                .header("Accept", "application/json").build()
        )
        if (code !in 200..299) throw IOException("DeepSeek HTTP $code: $body")
        val root = JSONObject(body)
        val infos = root.optJSONArray("balance_infos") ?: error("No balance_infos")
        var selected: JSONObject? = null
        for (currency in listOf("CNY", "USD")) {
            for (i in 0 until infos.length()) {
                val item = infos.optJSONObject(i) ?: continue
                if (item.optString("currency") == currency) { selected = item; break }
            }
            if (selected != null) break
        }
        if (selected == null && infos.length() > 0) selected = infos.optJSONObject(0)
        val info = selected ?: error("Unknown balance format")
        val currency = info.optString("currency")
        val symbol = when (currency) { "CNY" -> "¥"; "USD" -> "$"; else -> "$currency " }
        return UsageSnapshot(account.id, ProviderId.DEEPSEEK, balance = BalanceSnapshot(
            currency, symbol, info.optDouble("total_balance"), info.optDouble("granted_balance"),
            info.optDouble("topped_up_balance"), root.optBoolean("is_available", true)
        ))
    }

    private fun durationLabel(seconds: Long): String = when {
        seconds in 1..21_600 -> "${max(1, seconds / 3600)}h"
        seconds in 21_601..691_200 -> if (seconds >= 518_400) "周" else "${max(1, seconds / 86_400)}d"
        else -> "额度"
    }

    private fun kimiDurationSeconds(window: JSONObject): Long {
        val duration = window.optLong("duration", 0)
        val unit = window.optString("timeUnit", window.optString("time_unit")).uppercase().removePrefix("TIME_UNIT_")
        return when {
            unit.startsWith("SECOND") -> duration
            unit.startsWith("MINUTE") -> duration * 60
            unit.startsWith("HOUR") -> duration * 3600
            unit.startsWith("DAY") -> duration * 86400
            else -> 0
        }
    }

    private fun parseKimiDetail(detail: JSONObject, duration: Long, id: String): UsageWindow? {
        val limit = detail.optDouble("limit", 0.0)
        if (limit <= 0) return null
        val used = if (detail.has("used")) detail.optDouble("used") else limit - detail.optDouble("remaining", limit)
        val reset = listOf("resetAt", "reset_at", "resetTime", "reset_time")
            .firstNotNullOfOrNull { parseFlexibleEpoch(detail.opt(it)) }
            ?: listOf("resetIn", "reset_in", "ttl").firstNotNullOfOrNull { key -> detail.optLong(key, -1).takeIf { it >= 0 }?.let { nowEpoch() + it } }
        return UsageWindow(id, durationLabel(duration), ((limit - used) / limit * 100).coerceIn(0.0, 100.0), reset)
    }

    private fun parseFlexibleEpoch(value: Any?): Long? = when (value) {
        is Number -> value.toLong().let { if (it > 10_000_000_000L) it / 1000 else it }
        is String -> parseIsoEpoch(value)
        else -> null
    }

    private fun parseIsoEpoch(value: String): Long? = try { java.time.Instant.parse(value).epochSecond } catch (_: Exception) { null }
    private fun nowEpoch(): Long = System.currentTimeMillis() / 1000

    companion object {
        const val CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
        const val CLAUDE_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        const val KIMI_CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    }
}
