package top.ozero.aghmanage.client

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

data class InstalledApp(val packageName: String, val label: String)

/** 只读取有桌面入口的应用，避免申请 QUERY_ALL_PACKAGES。 */
object AppList {

    fun launcherApps(context: Context): List<InstalledApp> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }

        return resolved.asSequence()
            .mapNotNull { it.activityInfo?.applicationInfo }
            .distinctBy { it.packageName }
            .map {
                val label = runCatching { it.loadLabel(pm).toString() }.getOrDefault(it.packageName)
                InstalledApp(it.packageName, label)
            }
            .sortedBy { it.label.lowercase() }
            .toList()
    }
}
