package top.ozero.aghmanage.store

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import top.ozero.aghmanage.data.Profile

class ProfileStore(context: Context) {

    private val prefs: SharedPreferences = runCatching {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "agh_profile",
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }.getOrElse {
        // 少数设备 Keystore 异常时退回普通存储，避免应用直接无法启动
        context.getSharedPreferences("agh_profile_fallback", Context.MODE_PRIVATE)
    }

    fun load(): Profile = Profile(
        host = prefs.getString("host", "") ?: "",
        port = prefs.getInt("port", 80),
        https = prefs.getBoolean("https", false),
        user = prefs.getString("user", "root") ?: "root",
        pass = prefs.getString("pass", "") ?: ""
    )

    fun save(profile: Profile) {
        prefs.edit()
            .putString("host", profile.host)
            .putInt("port", profile.port)
            .putBoolean("https", profile.https)
            .putString("user", profile.user)
            .putString("pass", profile.pass)
            .apply()
    }

    fun clearPassword() {
        prefs.edit().putString("pass", "").apply()
    }
}
