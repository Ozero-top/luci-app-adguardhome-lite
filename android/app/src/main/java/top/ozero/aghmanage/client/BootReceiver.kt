package top.ozero.aghmanage.client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build

/** 开机后按上次状态自动开启客户端过滤。 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val prefs = ClientPrefs(context)
        if (!prefs.autoStart || !prefs.enabled) return

        // 未授权或被撤销时无法在后台自行建立 VPN，等用户下次打开应用处理
        if (VpnService.prepare(context) != null) return

        val service = Intent(context, AghVpnService::class.java)
            .setAction(AghVpnService.ACTION_START)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        }
    }
}
