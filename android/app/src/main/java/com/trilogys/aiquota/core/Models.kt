package com.trilogys.aiquota.core

import java.util.UUID

enum class ProviderId { CODEX, CLAUDE, KIMI, DEEPSEEK }

data class AccountRecord(
    val id: String = UUID.randomUUID().toString(),
    val provider: ProviderId,
    val name: String,
    val enabled: Boolean = true,
    val order: Int = 0
)

data class Credential(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresAtEpochSeconds: Long? = null,
    val accountId: String? = null,
    val clientId: String? = null
)

data class UsageWindow(
    val id: String,
    val label: String,
    val remainingPercent: Double,
    val resetAtEpochSeconds: Long? = null
)

data class BalanceSnapshot(
    val currency: String,
    val symbol: String,
    val total: Double,
    val granted: Double = 0.0,
    val toppedUp: Double = 0.0,
    val available: Boolean = true
)

data class UsageSnapshot(
    val accountId: String,
    val provider: ProviderId,
    val windows: List<UsageWindow> = emptyList(),
    val balance: BalanceSnapshot? = null,
    val updatedAtEpochSeconds: Long = System.currentTimeMillis() / 1000,
    val stale: Boolean = false,
    val errorMessage: String? = null
)
