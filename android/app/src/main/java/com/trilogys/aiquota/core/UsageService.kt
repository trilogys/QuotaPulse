package com.trilogys.aiquota.core

import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

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
        return ProviderParsers.codex(account.id, body)
    }

    private fun refreshCodex(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val form = FormBody.Builder()
            .add("grant_type", "refresh_token")
            .add("refresh_token", refresh)
            .add("client_id", credential.clientId ?: CODEX_CLIENT_ID)
            .build()
        val (code, body) = execute(
            Request.Builder().url("https://auth.openai.com/oauth/token").post(form)
                .header("Accept", "application/json").build()
        )
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
        return ProviderParsers.claude(account.id, body)
    }

    private fun refreshClaude(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val payload = JSONObject()
            .put("grant_type", "refresh_token")
            .put("refresh_token", refresh)
            .put("client_id", credential.clientId ?: CLAUDE_CLIENT_ID)
            .toString()
            .toRequestBody("application/json".toMediaType())
        val (code, body) = execute(
            Request.Builder().url("https://platform.claude.com/v1/oauth/token").post(payload)
                .header("Accept", "application/json").build()
        )
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
        return ProviderParsers.kimi(account.id, body)
    }

    private fun refreshKimi(accountId: String, credential: Credential): Credential {
        val refresh = credential.refreshToken ?: error("Missing refresh token")
        val form = FormBody.Builder()
            .add("client_id", credential.clientId ?: KIMI_CLIENT_ID)
            .add("grant_type", "refresh_token")
            .add("refresh_token", refresh)
            .build()
        val builder = Request.Builder().url("https://auth.kimi.com/api/oauth/token").post(form)
            .header("Accept", "application/json")
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
        return ProviderParsers.deepSeek(account.id, body)
    }

    private fun nowEpoch(): Long = System.currentTimeMillis() / 1000

    companion object {
        const val CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
        const val CLAUDE_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        const val KIMI_CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    }
}
