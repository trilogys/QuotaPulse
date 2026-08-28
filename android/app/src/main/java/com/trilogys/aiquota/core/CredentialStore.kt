package com.trilogys.aiquota.core

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject

class CredentialStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "aiquota_credentials",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun save(accountId: String, credential: Credential) {
        val headers = JSONObject()
        credential.deviceHeaders?.forEach { (key, value) -> headers.put(key, value) }
        val json = JSONObject()
            .put("accessToken", credential.accessToken)
            .put("refreshToken", credential.refreshToken)
            .put("expiresAt", credential.expiresAtEpochSeconds)
            .put("accountId", credential.accountId)
            .put("clientId", credential.clientId)
            .put("idToken", credential.idToken)
            .put("baseUrl", credential.baseUrl)
            .put("authenticationMode", credential.authenticationMode?.name)
            .put("deviceHeaders", headers)
        prefs.edit().putString(accountId, json.toString()).apply()
    }

    fun get(accountId: String): Credential? {
        val raw = prefs.getString(accountId, null) ?: return null
        val json = JSONObject(raw)
        val headersJson = json.optJSONObject("deviceHeaders")
        val headers = headersJson?.let { obj ->
            buildMap {
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    obj.optString(key).takeIf { it.isNotBlank() }?.let { put(key, it) }
                }
            }
        }?.takeIf { it.isNotEmpty() }
        return Credential(
            accessToken = json.getString("accessToken"),
            refreshToken = json.optString("refreshToken").takeIf { it.isNotBlank() && it != "null" },
            expiresAtEpochSeconds = json.optLong("expiresAt").takeIf { it > 0 },
            accountId = json.optString("accountId").takeIf { it.isNotBlank() && it != "null" },
            clientId = json.optString("clientId").takeIf { it.isNotBlank() && it != "null" },
            idToken = json.optString("idToken").takeIf { it.isNotBlank() && it != "null" },
            deviceHeaders = headers,
            baseUrl = json.optString("baseUrl").takeIf { it.isNotBlank() && it != "null" },
            authenticationMode = json.optString("authenticationMode").takeIf { it.isNotBlank() && it != "null" }
                ?.let { runCatching { CredentialAuthenticationMode.valueOf(it) }.getOrNull() }
        )
    }

    fun delete(accountId: String) {
        prefs.edit().remove(accountId).apply()
    }
}
