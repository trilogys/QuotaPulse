package com.trilogys.aiquota.core

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class AccountStore(context: Context) {
    private val prefs = context.getSharedPreferences("aiquota_state", Context.MODE_PRIVATE)

    fun accounts(): List<AccountRecord> {
        val raw = prefs.getString("accounts", "[]") ?: "[]"
        val array = JSONArray(raw)
        return buildList {
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                runCatching {
                    add(AccountRecord(
                        id = o.getString("id"),
                        provider = ProviderId.valueOf(o.getString("provider")),
                        name = o.optString("name", o.getString("provider")),
                        enabled = o.optBoolean("enabled", true),
                        order = o.optInt("order", i)
                    ))
                }
            }
        }.sortedWith(compareBy<AccountRecord> { it.order }.thenBy { it.name })
    }

    fun upsert(account: AccountRecord) {
        val items = accounts().toMutableList()
        val index = items.indexOfFirst { it.id == account.id }
        if (index >= 0) items[index] = account else items += account
        saveAccounts(items)
    }

    fun delete(accountId: String) {
        saveAccounts(accounts().filterNot { it.id == accountId })
        prefs.edit().remove("snapshot.$accountId").apply()
    }

    fun saveSnapshot(snapshot: UsageSnapshot) {
        val o = JSONObject()
            .put("accountId", snapshot.accountId)
            .put("provider", snapshot.provider.name)
            .put("updatedAt", snapshot.updatedAtEpochSeconds)
            .put("stale", snapshot.stale)
            .put("error", snapshot.errorMessage)
        val windows = JSONArray()
        snapshot.windows.forEach { w -> windows.put(JSONObject().put("id", w.id).put("label", w.label).put("remaining", w.remainingPercent).put("resetAt", w.resetAtEpochSeconds)) }
        o.put("windows", windows)
        snapshot.balance?.let { b -> o.put("balance", JSONObject().put("currency", b.currency).put("symbol", b.symbol).put("total", b.total).put("granted", b.granted).put("toppedUp", b.toppedUp).put("available", b.available)) }
        prefs.edit().putString("snapshot.${snapshot.accountId}", o.toString()).apply()
    }

    fun snapshot(accountId: String): UsageSnapshot? {
        val raw = prefs.getString("snapshot.$accountId", null) ?: return null
        return runCatching {
            val o = JSONObject(raw)
            val windowsArray = o.optJSONArray("windows") ?: JSONArray()
            val windows = buildList {
                for (i in 0 until windowsArray.length()) {
                    val w = windowsArray.getJSONObject(i)
                    add(UsageWindow(w.getString("id"), w.getString("label"), w.getDouble("remaining"), w.optLong("resetAt").takeIf { it > 0 }))
                }
            }
            val balance = o.optJSONObject("balance")?.let { b -> BalanceSnapshot(b.optString("currency"), b.optString("symbol"), b.optDouble("total"), b.optDouble("granted"), b.optDouble("toppedUp"), b.optBoolean("available", true)) }
            UsageSnapshot(accountId, ProviderId.valueOf(o.getString("provider")), windows, balance, o.optLong("updatedAt"), o.optBoolean("stale"), o.optString("error").takeIf { it.isNotBlank() && it != "null" })
        }.getOrNull()
    }

    fun markStale(accountId: String, error: String) {
        val old = snapshot(accountId)
        if (old != null) saveSnapshot(old.copy(stale = true, errorMessage = error))
    }

    private fun saveAccounts(items: List<AccountRecord>) {
        val array = JSONArray()
        items.forEach { a -> array.put(JSONObject().put("id", a.id).put("provider", a.provider.name).put("name", a.name).put("enabled", a.enabled).put("order", a.order)) }
        prefs.edit().putString("accounts", array.toString()).apply()
    }
}
