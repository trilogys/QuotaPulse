package com.trilogys.aiquota.core

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** Android codec for the shared ai-quota-native v1 JSON backup format. */
object PortableConfigCodec {
    const val FORMAT = "ai-quota-native"
    const val VERSION = 1

    data class ImportedAccount(val record: AccountRecord, val providerAccountId: String?, val credential: Credential?)

    fun encode(accounts: List<AccountRecord>, credentialFor: (String) -> Credential?, includeCredentials: Boolean): String {
        val items = JSONArray()
        accounts.forEach { account ->
            val item = JSONObject()
                .put("id", account.id)
                .put("provider", account.provider.name.lowercase())
                .put("label", account.name)
                .putNullable("providerAccountID", account.providerAccountId ?: credentialFor(account.id)?.accountId)
                .put("isEnabled", account.enabled)
                .put("sortOrder", account.order)
                .put("createdAt", Instant.ofEpochSecond(account.createdAtEpochSeconds).toString())
            if (includeCredentials) credentialFor(account.id)?.let { item.put("credential", credentialJson(it)) }
            items.put(item)
        }
        return JSONObject().put("format", FORMAT).put("version", VERSION).put("exportedAt", Instant.now().toString()).put("accounts", items).toString(2)
    }

    fun decode(raw: String): List<ImportedAccount> {
        val root = JSONObject(raw)
        require(root.optString("format") == FORMAT) { "Not a QuotaPulse configuration file" }
        val version = root.optInt("version", 0)
        require(version in 1..VERSION) { "Unsupported configuration version $version" }
        val array = root.getJSONArray("accounts")
        return buildList {
            for (i in 0 until array.length()) {
                val item = array.getJSONObject(i)
                val providerName = item.getString("provider")
                val provider = ProviderId.entries.firstOrNull { it.name.equals(providerName, true) } ?: error("Unknown provider: $providerName")
                val providerAccountId = item.stringOrNull("providerAccountID")
                val createdAt = item.stringOrNull("createdAt")?.let { runCatching { Instant.parse(it).epochSecond }.getOrNull() } ?: System.currentTimeMillis()/1000
                val record = AccountRecord(id=item.getString("id"), provider=provider, name=item.optString("label", provider.name), enabled=item.optBoolean("isEnabled", true), order=item.optInt("sortOrder", i), providerAccountId=providerAccountId, createdAtEpochSeconds=createdAt)
                add(ImportedAccount(record, providerAccountId, item.optJSONObject("credential")?.let(::credentialFromJson)))
            }
        }
    }

    private fun credentialJson(value: Credential) = JSONObject()
        .put("accessToken", value.accessToken).putNullable("refreshToken", value.refreshToken).putNullable("idToken", value.idToken)
        .putNullable("accountID", value.accountId).putNullable("expiresAt", value.expiresAtEpochSeconds?.let { Instant.ofEpochSecond(it).toString() })
        .putNullable("clientID", value.clientId).putNullable("baseURL", value.baseUrl)
        .putNullable("authenticationMode", value.authenticationMode?.let { if(it==CredentialAuthenticationMode.API_KEY)"apiKey" else "oauth" })
        .put("deviceHeaders", value.deviceHeaders?.let { JSONObject(it) } ?: JSONObject.NULL)

    private fun credentialFromJson(json: JSONObject): Credential {
        val headers = json.optJSONObject("deviceHeaders")?.let { obj -> obj.keys().asSequence().associateWith { obj.getString(it) } }
        val expires = json.stringOrNull("expiresAt")?.let { runCatching { Instant.parse(it).epochSecond }.getOrNull() }
        val mode=json.stringOrNull("authenticationMode")?.let{raw->CredentialAuthenticationMode.entries.firstOrNull{it.name.equals(raw,true)||it.name.replace("_","").equals(raw.replace("_",""),true)}}
        return Credential(accessToken=json.getString("accessToken"), refreshToken=json.stringOrNull("refreshToken"), expiresAtEpochSeconds=expires, accountId=json.stringOrNull("accountID"), clientId=json.stringOrNull("clientID"), idToken=json.stringOrNull("idToken"), deviceHeaders=headers, baseUrl=json.stringOrNull("baseURL"), authenticationMode=mode)
    }

    private fun JSONObject.putNullable(key:String,value:Any?):JSONObject=put(key,value ?: JSONObject.NULL)
    private fun JSONObject.stringOrNull(key:String):String?=if(!has(key)||isNull(key)) null else optString(key).takeIf{it.isNotBlank()}
}
