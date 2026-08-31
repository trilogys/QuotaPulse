package com.trilogys.quotapulse.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProviderParsersTest {
    @Test
    fun codexParsesDynamicWindows() {
        val body = """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 28,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 3600
                },
                "secondary_window": {
                  "used_percent": 61,
                  "limit_window_seconds": 604800,
                  "reset_at": 1800000000
                }
              }
            }
        """.trimIndent()

        val snapshot = ProviderParsers.codex("a", body, nowEpoch = 1_700_000_000)
        assertEquals(ProviderId.CODEX, snapshot.provider)
        assertEquals(2, snapshot.windows.size)
        assertEquals(72.0, snapshot.windows.first { it.label == "5h" }.remainingPercent, 0.001)
        assertEquals(39.0, snapshot.windows.first { it.label == "周" }.remainingPercent, 0.001)
        assertEquals(1_700_003_600L, snapshot.windows.first { it.label == "5h" }.resetAtEpochSeconds)
    }

    @Test
    fun claudeParsesFiveHourAndSevenDay() {
        val body = """
            {
              "five_hour": {"utilization": 37.5, "resets_at": "2026-08-27T12:00:00Z"},
              "seven_day": {"utilization": 70, "resets_at": "2026-08-30T00:00:00Z"}
            }
        """.trimIndent()

        val snapshot = ProviderParsers.claude("b", body)
        assertEquals(62.5, snapshot.windows.first { it.label == "5h" }.remainingPercent, 0.001)
        assertEquals(30.0, snapshot.windows.first { it.label == "周" }.remainingPercent, 0.001)
        assertTrue(snapshot.windows.all { it.resetAtEpochSeconds != null })
    }

    @Test
    fun kimiParsesLimitAndResetIn() {
        val body = """
            {
              "limits": [
                {
                  "window": {"duration": 5, "timeUnit": "HOUR"},
                  "detail": {"limit": 100, "used": 25, "resetIn": 600}
                }
              ],
              "usage": {"limit": 1000, "remaining": 800, "reset_in": 3600}
            }
        """.trimIndent()

        val snapshot = ProviderParsers.kimi("c", body, nowEpoch = 1_700_000_000)
        assertEquals(75.0, snapshot.windows.first { it.label == "5h" }.remainingPercent, 0.001)
        assertEquals(80.0, snapshot.windows.first { it.label == "周" }.remainingPercent, 0.001)
        assertEquals(1_700_000_600L, snapshot.windows.first { it.label == "5h" }.resetAtEpochSeconds)
    }

    @Test
    fun deepSeekPrefersCnyAndParsesBalance() {
        val body = """
            {
              "is_available": true,
              "balance_infos": [
                {"currency": "USD", "total_balance": "12.5", "granted_balance": "2", "topped_up_balance": "10.5"},
                {"currency": "CNY", "total_balance": "88.6", "granted_balance": "8.6", "topped_up_balance": "80"}
              ]
            }
        """.trimIndent()

        val snapshot = ProviderParsers.deepSeek("d", body)
        val balance = snapshot.balance!!
        assertEquals("CNY", balance.currency)
        assertEquals("¥", balance.symbol)
        assertEquals(88.6, balance.total, 0.001)
        assertTrue(balance.available)
    }

    @Test(expected = IllegalStateException::class)
    fun codexRejectsMissingContract() {
        ProviderParsers.codex("x", "{\"rate_limit\":{}}")
    }

    @Test(expected = IllegalStateException::class)
    fun claudeRejectsMissingContract() {
        ProviderParsers.claude("x", "{}")
    }

    @Test
    fun deepSeekAvailabilityCanBeFalse() {
        val snapshot = ProviderParsers.deepSeek(
            "x",
            "{\"is_available\":false,\"balance_infos\":[{\"currency\":\"USD\",\"total_balance\":\"1\"}]}"
        )
        assertFalse(snapshot.balance!!.available)
    }
}
