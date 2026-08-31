package com.trilogys.quotapulse.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.trilogys.quotapulse.core.Credential
import com.trilogys.quotapulse.core.CredentialAuthenticationMode
import com.trilogys.quotapulse.core.UsageService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.URLDecoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import kotlin.math.max

class OAuthManager(
    private val context: Context,
    private val client: OkHttpClient = OkHttpClient()
) {
    data class CodexPending(
        val verifier: String,
        val challenge: String,
        val state: String,
        val redirectUri: String,
        val port: Int
    )

    data class ClaudePending(val verifier: String)

    @Volatile private var codexPending: CodexPending? = null
    @Volatile private var claudePending: ClaudePending? = null

    suspend fun loginCodex(): Credential = withContext(Dispatchers.IO) {
        val server = openLoopbackServer()
        val pkce = pkce()
        val state = randomBase64Url(32)
        val redirectUri = "http://localhost:${server.localPort}/auth/callback"
        val pending = CodexPending(pkce.first, pkce.second, state, redirectUri, server.localPort)
        codexPending = pending
        val auth = codexAuthorizationUri(pending)
        withContext(Dispatchers.Main) { openBrowser(auth) }
        try {
            val callback = waitForCallback(server)
            completeCodexCallback(callback, pending)
        } finally {
            runCatching { server.close() }
        }
    }

    fun copyCodexAuthorizationLink(): String {
        val pkce = pkce()
        val pending = CodexPending(
            verifier = pkce.first,
            challenge = pkce.second,
            state = randomBase64Url(32),
            redirectUri = "http://localhost:1455/auth/callback",
            port = 1455
        )
        codexPending = pending
        return codexAuthorizationUri(pending).toString().also {
            copyText("Codex OAuth link", it)
        }
    }

    suspend fun completeCodexManual(callbackUrl: String): Credential = withContext(Dispatchers.IO) {
        val pending = codexPending ?: error("请先点击 Codex OAuth 开始授权")
        completeCodexCallback(callbackUrl.trim(), pending)
    }

    fun beginClaude(): String {
        val (url, verifier) = createClaudeAuthorization()
        openBrowser(url)
        return verifier
    }

    fun copyClaudeAuthorizationLink(): String {
        val (url, _) = createClaudeAuthorization()
        return url.toString().also { copyText("Claude OAuth link", it) }
    }

    private fun createClaudeAuthorization(): Pair<Uri, String> {
        val pkce = pkce()
        claudePending = ClaudePending(pkce.first)
        val url = Uri.parse("https://claude.ai/oauth/authorize").buildUpon()
            .appendQueryParameter("code", "true")
            .appendQueryParameter("client_id", UsageService.CLAUDE_CLIENT_ID)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("redirect_uri", "https://console.anthropic.com/oauth/code/callback")
            .appendQueryParameter("scope", "user:profile user:inference")
            .appendQueryParameter("code_challenge", pkce.second)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", pkce.first)
            .build()
        return url to pkce.first
    }

    suspend fun completeClaude(codeState: String): Credential = withContext(Dispatchers.IO) {
        val pending = claudePending ?: error("请先点击 Claude OAuth 开始授权")
        val raw = codeState.trim()
        val parts = raw.split("#", limit = 2)
        val code = parts.firstOrNull()?.takeIf { it.isNotBlank() } ?: error("缺少 Claude authorization code")
        val state = parts.getOrNull(1)?.takeIf { it.isNotBlank() } ?: pending.verifier
        val body = JSONObject()
            .put("grant_type", "authorization_code")
            .put("code", code)
            .put("state", state)
            .put("client_id", UsageService.CLAUDE_CLIENT_ID)
            .put("redirect_uri", "https://console.anthropic.com/oauth/code/callback")
            .put("code_verifier", pending.verifier)
            .toString().toRequestBody("application/json".toMediaType())
        val response = execute(Request.Builder().url("https://platform.claude.com/v1/oauth/token").post(body).header("Accept", "application/json").build())
        if (response.first !in 200..299) error("Claude token HTTP ${response.first}: ${response.second}")
        val json = JSONObject(response.second)
        claudePending = null
        Credential(
            accessToken = json.getString("access_token"),
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() },
            expiresAtEpochSeconds = json.optLong("expires_in").takeIf { it > 0 }?.let { System.currentTimeMillis() / 1000 + it },
            clientId = UsageService.CLAUDE_CLIENT_ID,
            authenticationMode = CredentialAuthenticationMode.OAUTH
        )
    }

    suspend fun loginKimi(
        copyAuthorizationLink: Boolean = false,
        onAuthorizationReady: (userCode: String?) -> Unit = {}
    ): Credential = withContext(Dispatchers.IO) {
        val headers = kimiDeviceHeaders()
        val firstForm = FormBody.Builder().add("client_id", UsageService.KIMI_CLIENT_ID).build()
        val firstRequest = Request.Builder().url("https://auth.kimi.com/api/oauth/device_authorization")
            .post(firstForm).apply { headers.forEach { (k, v) -> header(k, v) } }.header("Accept", "application/json").build()
        val (firstCode, firstBody) = execute(firstRequest)
        if (firstCode !in 200..299) error("Kimi device authorization HTTP $firstCode: $firstBody")
        val json = JSONObject(firstBody)
        val deviceCode = json.getString("device_code")
        val userCode = json.getString("user_code")
        val completeVerification = json.optString("verification_uri_complete").takeIf { it.isNotBlank() }
        val verification = completeVerification
            ?: json.optString("verification_uri").takeIf { it.isNotBlank() }
            ?: error("Kimi verification URL missing")
        withContext(Dispatchers.Main) {
            if (copyAuthorizationLink) {
                copyText("Kimi OAuth link", verification)
            } else {
                if (completeVerification == null) copyText("Kimi code", userCode)
                openBrowser(Uri.parse(verification))
            }
            onAuthorizationReady(if (completeVerification == null) userCode else null)
        }

        var interval = max(1L, json.optLong("interval", 5L))
        val deadline = System.currentTimeMillis() + max(60L, json.optLong("expires_in", 900L)) * 1000
        while (System.currentTimeMillis() < deadline) {
            delay(interval * 1000)
            val form = FormBody.Builder()
                .add("client_id", UsageService.KIMI_CLIENT_ID)
                .add("device_code", deviceCode)
                .add("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                .build()
            val request = Request.Builder().url("https://auth.kimi.com/api/oauth/token").post(form)
                .apply { headers.forEach { (k, v) -> header(k, v) } }.header("Accept", "application/json").build()
            val (code, bodyText) = execute(request)
            val body = runCatching { JSONObject(bodyText) }.getOrElse { JSONObject() }
            if (code in 200..299 && body.optString("access_token").isNotBlank()) {
                return@withContext Credential(
                    accessToken = body.getString("access_token"),
                    refreshToken = body.optString("refresh_token").takeIf { it.isNotBlank() },
                    expiresAtEpochSeconds = body.optLong("expires_in").takeIf { it > 0 }?.let { System.currentTimeMillis() / 1000 + it },
                    clientId = UsageService.KIMI_CLIENT_ID,
                    deviceHeaders = headers,
                    authenticationMode = CredentialAuthenticationMode.OAUTH
                )
            }
            when (body.optString("error")) {
                "authorization_pending", "" -> Unit
                "slow_down" -> interval += 5
                "expired_token", "access_denied" -> error("Kimi login: ${body.optString("error")}")
                else -> if (code < 500 && code != 429) error("Kimi login: ${body.optString("error", "HTTP $code")}")
            }
        }
        error("Kimi authorization timed out")
    }

    private fun completeCodexCallback(callbackUrl: String, pending: CodexPending): Credential {
        val uri = Uri.parse(callbackUrl)
        uri.getQueryParameter("error")?.let { error(uri.getQueryParameter("error_description") ?: it) }
        if (uri.getQueryParameter("state") != pending.state) error("OAuth state mismatch")
        val code = uri.getQueryParameter("code")?.takeIf { it.isNotBlank() } ?: error("Missing authorization code")
        val form = FormBody.Builder()
            .add("grant_type", "authorization_code")
            .add("code", code)
            .add("redirect_uri", pending.redirectUri)
            .add("client_id", UsageService.CODEX_CLIENT_ID)
            .add("code_verifier", pending.verifier)
            .build()
        val response = execute(Request.Builder().url("https://auth.openai.com/oauth/token").post(form).header("Accept", "application/json").build())
        if (response.first !in 200..299) error("Codex token HTTP ${response.first}: ${response.second}")
        val json = JSONObject(response.second)
        val idToken = json.optString("id_token").takeIf { it.isNotBlank() }
        codexPending = null
        return Credential(
            accessToken = json.getString("access_token"),
            refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() },
            idToken = idToken,
            accountId = findJwtClaim(idToken, "chatgpt_account_id"),
            clientId = UsageService.CODEX_CLIENT_ID,
            authenticationMode = CredentialAuthenticationMode.OAUTH
        )
    }

    private fun codexAuthorizationUri(pending: CodexPending): Uri =
        Uri.parse("https://auth.openai.com/oauth/authorize").buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", UsageService.CODEX_CLIENT_ID)
            .appendQueryParameter("redirect_uri", pending.redirectUri)
            .appendQueryParameter("scope", "openid profile email offline_access api.connectors.read api.connectors.invoke")
            .appendQueryParameter("code_challenge", pending.challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("id_token_add_organizations", "true")
            .appendQueryParameter("codex_cli_simplified_flow", "true")
            .appendQueryParameter("state", pending.state)
            .appendQueryParameter("originator", "codex_cli_rs")
            .build()

    private fun openLoopbackServer(): ServerSocket = runCatching { ServerSocket(1455, 1) }.getOrElse { ServerSocket(1457, 1) }

    private fun waitForCallback(server: ServerSocket): String {
        server.soTimeout = 300_000
        server.accept().use { socket ->
            val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
            val requestLine = reader.readLine() ?: error("Empty OAuth callback")
            val path = requestLine.split(" ").getOrNull(1) ?: error("Invalid OAuth callback")
            val host = if (server.localPort == 1455) "localhost" else "localhost:${server.localPort}"
            val callback = if (server.localPort == 1455) "http://localhost$path" else "http://$host$path"
            val html = "<html><body><h3>QuotaPulse authorization complete.</h3><p>You can return to the app.</p></body></html>"
            val bytes = html.toByteArray()
            socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
            socket.getOutputStream().write(bytes)
            socket.getOutputStream().flush()
            return callback
        }
    }

    private fun openBrowser(uri: Uri) {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun copyText(label: String, value: String) {
        android.content.ClipboardManager::class.java.cast(context.getSystemService(Context.CLIPBOARD_SERVICE))
            ?.setPrimaryClip(android.content.ClipData.newPlainText(label, value))
    }

    private fun execute(request: Request): Pair<Int, String> = client.newCall(request).execute().use { it.code to it.body?.string().orEmpty() }

    private fun pkce(): Pair<String, String> {
        val verifier = randomBase64Url(64)
        val challenge = Base64.getUrlEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
        return verifier to challenge
    }

    private fun randomBase64Url(bytes: Int): String {
        val data = ByteArray(bytes).also(SecureRandom()::nextBytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(data)
    }

    private fun kimiDeviceHeaders(): Map<String, String> = mapOf(
        "X-Msh-Platform" to "kimi_cli",
        "X-Msh-Version" to "QuotaPulse",
        "X-Msh-Device-Name" to Build.MODEL,
        "X-Msh-Device-Model" to Build.DEVICE,
        "X-Msh-Os-Version" to Build.VERSION.RELEASE,
        "X-Msh-Device-Id" to UUID.randomUUID().toString()
    )

    private fun findJwtClaim(token: String?, key: String): String? {
        if (token.isNullOrBlank()) return null
        return runCatching {
            val payload = token.split(".").getOrNull(1) ?: return@runCatching null
            val decoded = String(Base64.getUrlDecoder().decode(payload.padEnd((payload.length + 3) / 4 * 4, '=')))
            findNested(JSONObject(decoded), key)
        }.getOrNull()
    }

    private fun findNested(value: Any?, key: String): String? {
        when (value) {
            is JSONObject -> {
                if (value.has(key) && value.opt(key) is String) return value.optString(key)
                val keys = value.keys()
                while (keys.hasNext()) findNested(value.opt(keys.next()), key)?.let { return it }
            }
            is org.json.JSONArray -> for (i in 0 until value.length()) findNested(value.opt(i), key)?.let { return it }
        }
        return null
    }
}
