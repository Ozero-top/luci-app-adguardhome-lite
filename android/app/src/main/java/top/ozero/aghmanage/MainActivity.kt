package top.ozero.aghmanage

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import top.ozero.aghmanage.data.AghClient
import top.ozero.aghmanage.store.ProfileStore
import top.ozero.aghmanage.ui.AghTheme
import top.ozero.aghmanage.ui.ClientScreen
import top.ozero.aghmanage.ui.LoginScreen
import top.ozero.aghmanage.ui.RootScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AghTheme {
                val context = LocalContext.current
                val store = remember { ProfileStore(context) }
                var profile by remember { mutableStateOf(store.load()) }
                var client by remember { mutableStateOf<AghClient?>(null) }
                var clientOnly by remember { mutableStateOf(false) }

                val current = client
                when {
                    clientOnly -> {
                        BackHandler { clientOnly = false }
                        ClientScreen(onBack = { clientOnly = false })
                    }
                    current == null -> {
                        LoginScreen(
                            initial = profile,
                            onClientOnly = { clientOnly = true },
                            onLogin = { target ->
                                val created = AghClient(target)
                                withContext(Dispatchers.IO) { created.connect() }
                                store.save(target)
                                profile = target
                                client = created
                            }
                        )
                    }
                    else -> {
                        RootScreen(
                            client = current,
                            onLogout = {
                                store.clearPassword()
                                profile = profile.copy(pass = "")
                                client = null
                            }
                        )
                    }
                }
            }
        }
    }
}
