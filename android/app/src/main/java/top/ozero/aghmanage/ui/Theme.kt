package top.ozero.aghmanage.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF4F7D3A),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE9F0DF),
    onPrimaryContainer = Color(0xFF2F3B2A),
    background = Color(0xFFF3EDDF),
    onBackground = Color(0xFF2F3B2A),
    surface = Color(0xFFFFFDF7),
    onSurface = Color(0xFF2F3B2A),
    surfaceVariant = Color(0xFFFAF5EA),
    onSurfaceVariant = Color(0xFF6F7566),
    outline = Color(0xFFD3C6A9),
    error = Color(0xFFB04A3A)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8FBF71),
    onPrimary = Color(0xFF14210F),
    primaryContainer = Color(0xFF2C3A26),
    onPrimaryContainer = Color(0xFFE5F0DA),
    background = Color(0xFF141517),
    onBackground = Color(0xFFE6E6E6),
    surface = Color(0xFF1D1F21),
    onSurface = Color(0xFFE6E6E6),
    surfaceVariant = Color(0xFF26282A),
    onSurfaceVariant = Color(0xFFA6A9A3),
    outline = Color(0xFF3A3D3F),
    error = Color(0xFFE08A7C)
)

@Composable
fun AghTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}
