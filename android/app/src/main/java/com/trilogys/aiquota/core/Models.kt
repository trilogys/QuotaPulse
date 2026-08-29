package com.trilogys.aiquota.core

import java.util.UUID

enum class ProviderId { CODEX, CLAUDE, KIMI, DEEPSEEK, MINIMAX, GLM, COPILOT }
enum class CredentialAuthenticationMode { OAUTH, API_KEY }

enum class ProviderErrorKind {
    AUTHENTICATION, RATE_LIMITED, PROVIDER_UNAVAILABLE, NETWORK, INVALID_RESPONSE, CONFIGURATION, UNKNOWN;
    val label:String get()=when(this){AUTHENTICATION->"登录失效";RATE_LIMITED->"限流";PROVIDER_UNAVAILABLE->"服务异常";NETWORK->"网络异常";INVALID_RESPONSE->"数据异常";CONFIGURATION->"配置异常";UNKNOWN->"刷新失败"}
}

data class AccountRecord(
    val id:String=UUID.randomUUID().toString(),
    val provider:ProviderId,
    val name:String,
    val enabled:Boolean=true,
    val order:Int=0,
    val providerAccountId:String?=null,
    val createdAtEpochSeconds:Long=System.currentTimeMillis()/1000
)
data class Credential(val accessToken:String,val refreshToken:String?=null,val expiresAtEpochSeconds:Long?=null,val accountId:String?=null,val clientId:String?=null,val idToken:String?=null,val deviceHeaders:Map<String,String>?=null,val baseUrl:String?=null,val authenticationMode:CredentialAuthenticationMode?=null)
data class UsageWindow(val id:String,val label:String,val remainingPercent:Double,val resetAtEpochSeconds:Long?=null)
data class BalanceSnapshot(val currency:String,val symbol:String,val total:Double,val granted:Double=0.0,val toppedUp:Double=0.0,val available:Boolean=true)
data class UsageSnapshot(val accountId:String,val provider:ProviderId,val windows:List<UsageWindow> = emptyList(),val balance:BalanceSnapshot?=null,val updatedAtEpochSeconds:Long=System.currentTimeMillis()/1000,val stale:Boolean=false,val errorMessage:String?=null,val errorKind:ProviderErrorKind?=null,val connectionLabel:String?=null,val availableModels:List<String> = emptyList())

object ProviderErrorClassifier {
    fun classify(message:String?):ProviderErrorKind { val raw=message.orEmpty().lowercase();return when { raw.contains("401")||raw.contains("403")||raw.contains("authentication expired")||raw.contains("missing credential")->ProviderErrorKind.AUTHENTICATION;raw.contains("429")||raw.contains("rate limit")->ProviderErrorKind.RATE_LIMITED;raw.contains("500")||raw.contains("502")||raw.contains("503")||raw.contains("504")||raw.contains("temporarily unavailable")->ProviderErrorKind.PROVIDER_UNAVAILABLE;raw.contains("network")||raw.contains("connection")||raw.contains("timeout")||raw.contains("dns")->ProviderErrorKind.NETWORK;raw.contains("response format")||raw.contains("json")||raw.contains("parse")||raw.contains("unexpected")->ProviderErrorKind.INVALID_RESPONSE;raw.contains("configuration")||raw.contains("base url")->ProviderErrorKind.CONFIGURATION;else->ProviderErrorKind.UNKNOWN } }
}
