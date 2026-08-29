package com.trilogys.aiquota.ui

import android.app.Activity
import android.content.Context
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.trilogys.aiquota.core.ProviderId

enum class DashboardThemeOption {
    DAYLIGHT,
    NEON,
    GRAPHITE,
    AURORA
}

@Immutable
data class DashboardPalette(
    val background: Color,
    val backgroundAccent: Color,
    val surface: Color,
    val surfaceRaised: Color,
    val border: Color,
    val primaryText: Color,
    val secondaryText: Color,
    val primary: Color,
    val secondary: Color,
    val success: Color,
    val warning: Color,
    val cardCornerRadius: Int,
    val compactCornerRadius: Int
) {
    fun accent(provider: ProviderId): Color = when {
        this === DaylightPalette -> when (provider) {
            ProviderId.CODEX -> Color(0xFFED571A)
            ProviderId.CLAUDE -> Color(0xFFF51A47)
            ProviderId.KIMI -> Color(0xFF29A657)
            ProviderId.DEEPSEEK -> Color(0xFF14948C)
            ProviderId.MINIMAX -> Color(0xFFF5991A)
            ProviderId.GLM -> Color(0xFF3D7DE0)
            ProviderId.COPILOT -> Color(0xFF8A59C7)
        }
        provider == ProviderId.CODEX -> primary
        provider == ProviderId.CLAUDE -> warning
        provider == ProviderId.KIMI -> success
        provider == ProviderId.DEEPSEEK -> secondary
        provider == ProviderId.MINIMAX && this === GraphitePalette -> Color(0xFFE0B847)
        provider == ProviderId.MINIMAX -> Color(0xFFF2A62E)
        provider == ProviderId.GLM && this === AuroraPalette -> Color(0xFF6B94FA)
        provider == ProviderId.GLM -> Color(0xFF4D87FA)
        else -> Color(0xFFC773EB)
    }
}

private val DaylightPalette = DashboardPalette(
    background = Color(0xFFF0F1F2),
    backgroundAccent = Color(0xFFDEDFE3),
    surface = Color.White,
    surfaceRaised = Color(0xFFECEDEF),
    border = Color(0x15000000),
    primaryText = Color(0xFF14171F),
    secondaryText = Color(0xFF5C6473),
    primary = Color(0xFFED571A),
    secondary = Color(0xFFF51A47),
    success = Color(0xFF29A657),
    warning = Color(0xFFF0642E),
    cardCornerRadius = 24,
    compactCornerRadius = 18
)

private val NeonPalette = DashboardPalette(
    background = Color(0xFF090A0E),
    backgroundAccent = Color(0xFF130E21),
    surface = Color(0xFF16171D),
    surfaceRaised = Color(0xFF1D1F26),
    border = Color(0x1FFFFFFF),
    primaryText = Color.White,
    secondaryText = Color(0xFF9EA3B8),
    primary = Color(0xFF7D33F5),
    secondary = Color(0xFF40D1CC),
    success = Color(0xFF33C773),
    warning = Color(0xFFF0642E),
    cardCornerRadius = 22,
    compactCornerRadius = 16
)

private val GraphitePalette = DashboardPalette(
    background = Color(0xFF0B0D0E),
    backgroundAccent = Color(0xFF131516),
    surface = Color(0xFF17191A),
    surfaceRaised = Color(0xFF212324),
    border = Color(0x1FFFFFFF),
    primaryText = Color.White,
    secondaryText = Color(0xFF9EA3B8),
    primary = Color(0xFF33C299),
    secondary = Color(0xFFF28730),
    success = Color(0xFF54BD70),
    warning = Color(0xFFF0642E),
    cardCornerRadius = 22,
    compactCornerRadius = 16
)

private val AuroraPalette = DashboardPalette(
    background = Color(0xFF06120F),
    backgroundAccent = Color(0xFF0A1F1A),
    surface = Color(0xFF111B18),
    surfaceRaised = Color(0xFF17251F),
    border = Color(0x1FFFFFFF),
    primaryText = Color.White,
    secondaryText = Color(0xFF9EA3B8),
    primary = Color(0xFF38D1CC),
    secondary = Color(0xFF9E57F0),
    success = Color(0xFF33C773),
    warning = Color(0xFFF0642E),
    cardCornerRadius = 22,
    compactCornerRadius = 16
)

private fun DashboardThemeOption.palette(): DashboardPalette = when (this) {
    DashboardThemeOption.DAYLIGHT -> DaylightPalette
    DashboardThemeOption.NEON -> NeonPalette
    DashboardThemeOption.GRAPHITE -> GraphitePalette
    DashboardThemeOption.AURORA -> AuroraPalette
}

val LocalDashboardPalette = staticCompositionLocalOf { DaylightPalette }

object DashboardThemePreferences {
    private const val PreferencesName = "quotapulse_ui"
    private const val ThemeKey = "dashboard_theme"

    fun load(context: Context): DashboardThemeOption {
        val raw = context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .getString(ThemeKey, DashboardThemeOption.DAYLIGHT.name)
        return runCatching { DashboardThemeOption.valueOf(raw.orEmpty()) }
            .getOrDefault(DashboardThemeOption.DAYLIGHT)
    }

    fun save(context: Context, theme: DashboardThemeOption) {
        context.getSharedPreferences(PreferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(ThemeKey, theme.name)
            .apply()
    }
}

@Composable
fun QuotaPulseTheme(
    option: DashboardThemeOption,
    content: @Composable () -> Unit
) {
    val palette = option.palette()
    val isLight = option == DashboardThemeOption.DAYLIGHT
    val colors = if (isLight) {
        lightColorScheme(
            primary = palette.primary,
            secondary = palette.secondary,
            tertiary = palette.success,
            background = palette.background,
            surface = palette.surface,
            surfaceVariant = palette.surfaceRaised,
            onPrimary = Color.White,
            onSecondary = Color.White,
            onBackground = palette.primaryText,
            onSurface = palette.primaryText,
            onSurfaceVariant = palette.secondaryText,
            outline = palette.border
        )
    } else {
        darkColorScheme(
            primary = palette.primary,
            secondary = palette.secondary,
            tertiary = palette.success,
            background = palette.background,
            surface = palette.surface,
            surfaceVariant = palette.surfaceRaised,
            onPrimary = Color.White,
            onSecondary = Color.White,
            onBackground = palette.primaryText,
            onSurface = palette.primaryText,
            onSurfaceVariant = palette.secondaryText,
            outline = palette.border
        )
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            window.statusBarColor = palette.background.toArgb()
            window.navigationBarColor = palette.background.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = isLight
                isAppearanceLightNavigationBars = isLight
            }
        }
    }

    CompositionLocalProvider(LocalDashboardPalette provides palette) {
        MaterialTheme(colorScheme = colors, content = content)
    }
}
