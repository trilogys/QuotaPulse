package com.trilogys.aiquota.core

import org.json.JSONObject
import kotlin.math.max

internal object ProviderParsers {
    fun codex(accountId: String, body: String, nowEpoch: Long = System.currentTimeMillis() / 1000): UsageSnapshot {
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
                    raw.optLong("reset_after_seconds", -1L) >= 0 -> nowEpoch + raw.optLong("reset_after_seconds")
                    else -> null
                }
                add(UsageWindow("codex-$key", durationLabel(duration), 100.0 - raw.optDouble("used_percent"), reset))
            }
        }.distinctBy { it.label }
        if (windows.isEmpty()) error("No Codex quota windows")
        return UsageSnapshot(accountId, ProviderId.CODEX, windows = windows)
    }

    fun claude(accountId: String, body: String): UsageSnapshot {
        val root = JSONObject(body)
        val windows = buildList {
            root.optJSONObject("five_hour")?.let {
                add(UsageWindow("claude-5h", "5h", 100 - it.optDouble("utilization"), parseIsoEpoch(it.optString("resets_at"))))
            }
            root.optJSONObject("seven_day")?.let {
                add(UsageWindow("claude-week", "周", 100 - it.optDouble("utilization"), parseIsoEpoch(it.optString("resets_at"))))
            }
        }
        if (windows.isEmpty()) error("No Claude quota windows")
        return UsageSnapshot(accountId, ProviderId.CLAUDE, windows = windows)
    }

    fun kimi(accountId: String, body: String, nowEpoch: Long = System.currentTimeMillis() / 1000): UsageSnapshot {
        val root = JSONObject(body)
        val windows = mutableListOf<UsageWindow>()
        root.optJSONArray("limits")?.let { limits ->
            for (i in 0 until limits.length()) {
                val entry = limits.optJSONObject(i) ?: continue
                val window = entry.optJSONObject("window") ?: entry
                val detail = entry.optJSONObject("detail") ?: entry
                parseKimiDetail(detail, kimiDurationSeconds(window), "kimi-$i", nowEpoch)?.let(windows::add)
            }
        }
        root.optJSONObject("usage")?.let { usage ->
            if (windows.none { it.label == "周" }) {
                parseKimiDetail(usage, 604_800, "kimi-week-summary", nowEpoch)?.let(windows::add)
            }
        }
        val distinct = windows.distinctBy { it.label }
        if (distinct.isEmpty()) error("No Kimi quota windows")
        return UsageSnapshot(accountId, ProviderId.KIMI, windows = distinct)
    }

    fun deepSeek(accountId: String, body: String): UsageSnapshot {
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
        return UsageSnapshot(accountId, ProviderId.DEEPSEEK, balance = BalanceSnapshot(
            currency = currency,
            symbol = symbol,
            total = info.optDouble("total_balance"),
            granted = info.optDouble("granted_balance"),
            toppedUp = info.optDouble("topped_up_balance"),
            available = root.optBoolean("is_available", true)
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

    private fun parseKimiDetail(detail: JSONObject, duration: Long, id: String, nowEpoch: Long): UsageWindow? {
        val limit = detail.optDouble("limit", 0.0)
        if (limit <= 0) return null
        val used = if (detail.has("used")) detail.optDouble("used") else limit - detail.optDouble("remaining", limit)
        val reset = listOf("resetAt", "reset_at", "resetTime", "reset_time")
            .firstNotNullOfOrNull { parseFlexibleEpoch(detail.opt(it)) }
            ?: listOf("resetIn", "reset_in", "ttl").firstNotNullOfOrNull { key ->
                detail.optLong(key, -1).takeIf { it >= 0 }?.let { nowEpoch + it }
            }
        return UsageWindow(id, durationLabel(duration), ((limit - used) / limit * 100).coerceIn(0.0, 100.0), reset)
    }

    private fun parseFlexibleEpoch(value: Any?): Long? = when (value) {
        is Number -> value.toLong().let { if (it > 10_000_000_000L) it / 1000 else it }
        is String -> parseIsoEpoch(value)
        else -> null
    }

    private fun parseIsoEpoch(value: String): Long? = try { java.time.Instant.parse(value).epochSecond } catch (_: Exception) { null }
}
