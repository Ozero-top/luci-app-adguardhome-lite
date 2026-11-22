package top.ozero.aghmanage.client

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class ClientSnapshot(
    val running: Boolean = false,
    val pausedUntil: Long = 0L,
    val blocked: Long = 0L,
    val rules: Int = 0,
    val updateMessage: String = ""
) {
    fun isPaused(now: Long = System.currentTimeMillis()): Boolean = pausedUntil > now
}

/** VPN 服务与界面共享的运行时状态（同一进程）。 */
object ClientState {
    private val _flow = MutableStateFlow(ClientSnapshot())
    val flow: StateFlow<ClientSnapshot> = _flow

    fun snapshot(): ClientSnapshot = _flow.value

    fun update(transform: (ClientSnapshot) -> ClientSnapshot) {
        _flow.update(transform)
    }
}
