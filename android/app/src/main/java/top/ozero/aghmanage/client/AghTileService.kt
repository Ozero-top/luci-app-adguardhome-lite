package top.ozero.aghmanage.client

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** 快捷设置磁贴：开启过滤，或暂停 / 恢复 30 秒。 */
class AghTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    private fun updateTile() {
        val prefs = ClientPrefs(this)
        val running = prefs.enabled
        val paused = prefs.pausedUntil > System.currentTimeMillis()
        qsTile?.apply {
            state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = "AGHTools 过滤"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = when {
                    !running -> "点击开启"
                    paused -> "已暂停，点击恢复"
                    else -> "点击暂停 30 秒"
                }
            }
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val prefs = ClientPrefs(this)

        if (!prefs.enabled) {
            val prepare = VpnService.prepare(this)
            if (prepare != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startActivityAndCollapse(
                        PendingIntent.getActivity(
                            this,
                            0,
                            prepare,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    startActivityAndCollapse(prepare)
                }
            } else {
                startFilter()
            }
        } else {
            startServiceSafe(
                Intent(this, AghVpnService::class.java)
                    .setAction(AghVpnService.ACTION_TOGGLE_PAUSE)
            )
        }
        updateTile()
    }

    private fun startServiceSafe(intent: Intent) {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }
    }

    private fun startFilter() {
        startServiceSafe(
            Intent(this, AghVpnService::class.java)
                .setAction(AghVpnService.ACTION_START)
        )
    }
}
