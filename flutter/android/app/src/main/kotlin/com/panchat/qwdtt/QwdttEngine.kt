// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.content.Context
import android.content.Intent
import com.bitchat.android.net.route.*
import com.bitchat.android.net.importprofile.QwdttSubscriptionImport
import com.bitchat.android.net.vk.VkTransportCaptcha
import com.google.gson.Gson
import com.panchat.tor.NativeTorManager
import com.panchat.tor.TorConfiguration
import java.io.File
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.*

/** One serialized lifetime owner for both protected app-local transports. */
class QwdttEngine private constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: QwdttEngine? = null
        fun get(context: Context): QwdttEngine = instance ?: synchronized(this) {
            instance ?: QwdttEngine(context.applicationContext).also { instance = it }
        }
        fun randomSecret(): String = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(24).also(SecureRandom()::nextBytes))
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val profiles = QwdttProfiles(context)
    private val prefs = context.getSharedPreferences("kachat_network", Context.MODE_PRIVATE)
    private val secretStore = NetworkSecretStore.create(context)
    private val metadata = QwdttProfileMetadataCache { profiles.load() }
    val vkSession by lazy { com.bitchat.android.net.vk.VkSessionRepository(secretStore) }
    private val tor = NativeTorManager(context)
    private var backend: NetworkBackend? = null
    private var job: Job? = null
    private var teardown: Job? = null
    private var generation = 0L
    @Volatile private var state = "STOPPED"
    @Volatile private var endpoint: SocksEndpoint? = null
    @Volatile private var publicError: String? = null
    private var initialized = false
    private val route: String get() = NetworkSelection.resolve(prefs.getString("route", null), profiles.selected)
    private fun selectRoute(value: String) {
        require(value in listOf("DIRECT", "VK", "TOR"))
        check(prefs.edit().putString("route", value).commit())
        profiles.selected = NetworkSelection.protected(value)
    }

    @Synchronized fun initialize(): Map<String, Any?> {
        if (!initialized) {
            initialized = true
            try {
                when (route) {
                    "VK" -> profiles.activeId?.let { connect(it) } ?: run { state = "ERROR"; publicError = "Выберите профиль qWDTT." }
                    "TOR" -> { val config = torSettings(); connectTor(config["mode"] as String, config["bridges"] as String, config["socksPort"] as Int) }
                    "BLOCKED" -> { state = "ERROR"; publicError = "Настройки маршрута повреждены. Выберите подключение заново." }
                }
            } catch (_: Exception) { endpoint = null; state = "ERROR"; publicError = "Не удалось восстановить выбранный маршрут." }
        }
        return snapshot()
    }

    @Synchronized fun select(selectedRoute: String = "VK") {
        // Invalidate the old endpoint before publishing a new route preference.
        stop(false, stopService = false)
        selectRoute(selectedRoute)
    }
    @Synchronized fun serviceDestroyed(epoch: Long) { if (generation == epoch) stop(false, stopService = false) }

    /** Cancel bootstrap, then serialize cleanup before any replacement core starts. */
    @Synchronized fun stop(direct: Boolean, stopService: Boolean = true) {
        val epoch = ++generation
        val previous = job; previous?.cancel(); job = null
        val oldBackend = backend; backend = null
        val priorCleanup = teardown
        endpoint = null; state = "STOPPED"; publicError = null
        if (direct) selectRoute("DIRECT")
        VkTransportCaptcha.cancelPending()
        teardown = scope.launch {
            priorCleanup?.join()
            previous?.join()
            runCatching { oldBackend?.stop() }
            runCatching { tor.stop() }
        }
        NetworkDiagnostics.log.record(if (route == "TOR") NetworkRoute.TOR else NetworkRoute.VK, NetworkStage.STOPPED)
        if (stopService) context.stopService(Intent(context, QwdttService::class.java))
    }

    @Synchronized fun connect(id: String) {
        val selected = profiles.load().first { it.profile.id == id }
        require(!selected.secrets["vk-hash"].isNullOrBlank() && !selected.secrets["vk-password"].isNullOrBlank())
        selectRoute("VK"); profiles.activeId = id
        begin("VK") {
            val core = vkBackend(File(context.applicationInfo.nativeLibraryDir, "libbitchat_vk.so"),
                File(context.noBackupFilesDir, "qwdtt")) { reference -> selected.secrets[reference.substringAfter(':')] }
            synchronized(this@QwdttEngine) { backend = core }
            core.start(selected.profile)
        }
    }

    @Synchronized fun torSettings(): Map<String, Any> = mapOf(
        "mode" to (prefs.getString("torMode", "WEBTUNNEL") ?: "WEBTUNNEL"),
        "socksPort" to prefs.getInt("torPort", 19050),
        "bridges" to (secretStore.get("tor:bridges") ?: ""),
    )

    @Synchronized fun connectTor(mode: String, bridges: String, port: Int) {
        require(port in 1024..65535 && bridges.toByteArray(Charsets.UTF_8).size <= 65536)
        TorConfiguration.bridgeLines(bridges, mode)
        secretStore.put("tor:bridges", bridges)
        check(prefs.edit().putString("torMode", mode).putInt("torPort", port).commit())
        selectRoute("TOR")
        begin("TOR") { tor.start(bridges, mode, port) }
    }

    @Synchronized private fun begin(selectedRoute: String, start: suspend () -> SocksEndpoint) {
        stop(false, stopService = false)
        val cleanup = teardown
        val epoch = ++generation
        endpoint = null; state = "STARTING"; publicError = null
        NetworkDiagnostics.log.clear()
        NetworkDiagnostics.log.record(if (selectedRoute == "TOR") NetworkRoute.TOR else NetworkRoute.VK, NetworkStage.STARTING)
        context.startForegroundService(Intent(context, QwdttService::class.java).putExtra("generation", epoch).putExtra("route", selectedRoute))
        job = scope.launch {
            cleanup?.join()
            try {
                ensureActive()
                val ready = start()
                synchronized(this@QwdttEngine) { if (generation == epoch) { endpoint = ready; state = "READY" } }
            } catch (cancel: CancellationException) {
                synchronized(this@QwdttEngine) {
                    if (generation == epoch) {
                        endpoint = null; state = "ERROR"
                        publicError = if (cancel is TimeoutCancellationException) "Время подключения истекло. Повторите попытку." else "Подключение прервано. Повторите попытку."
                    }
                }
                throw cancel
            }
            catch (_: Exception) {
                synchronized(this@QwdttEngine) {
                    if (generation == epoch) {
                        endpoint = null; state = "ERROR"
                        publicError = if (selectedRoute == "TOR") "Tor не подключился. Проверьте мосты и сведения о подключении."
                            else diagnosticHint(NetworkDiagnostics.log.events.value) ?: "qWDTT не подключился. Проверьте сервер и реквизиты."
                    }
                }
            }
        }
    }

    @Synchronized fun export(id: String): String {
        val selected = profiles.load().first { it.profile.id == id }
        return QwdttSubscriptionImport.export(selected.profile, requireNotNull(selected.secrets["vk-password"]), requireNotNull(selected.secrets["vk-hash"]))
    }

    @Synchronized fun import(source: String) {
        val additions = QwdttSubscriptionImport.parse(source).map {
            StoredQwdtt(it.profile, it.secrets.toMutableMap().apply { put("proxy-password", randomSecret()) })
        }
        profiles.save(profiles.load() + additions); metadata.invalidate()
    }

    @Synchronized fun save(json: String, password: String?, hash: String?) {
        require(json.length <= 16384)
        val profile = Gson().fromJson(json, NetworkProfile::class.java)
        require(profile.route == NetworkRoute.VK); profile.validate()
        require(profile.serverHost.isNotBlank())
        val rows = profiles.load().toMutableList()
        val previous = rows.firstOrNull { it.profile.id == profile.id }
        val secrets = previous?.secrets?.toMutableMap() ?: mutableMapOf("proxy-password" to randomSecret())
        if (!password.isNullOrEmpty()) { require(password.length <= 4096); secrets["vk-password"] = password }
        if (!hash.isNullOrEmpty()) { require(hash.length in 16..4096 && hash.none(Char::isISOControl) && ',' !in hash); secrets["vk-hash"] = com.bitchat.android.net.vk.VkOAuthParser.callHash(hash) }
        require(!secrets["vk-password"].isNullOrEmpty())
        rows.removeAll { it.profile.id == profile.id }; rows.add(StoredQwdtt(profile, secrets)); profiles.save(rows); metadata.invalidate()
        if (route == "VK" && profiles.activeId == profile.id) connect(profile.id)
    }

    @Synchronized fun delete(id: String) {
        if (profiles.activeId == id) { if (route == "VK") stop(false); profiles.activeId = null }
        profiles.save(profiles.load().filterNot { it.profile.id == id }); metadata.invalidate()
    }


    @Synchronized fun snapshot(): Map<String, Any?> {
        if (route == "VK" && (state == "READY" || state == "RECONNECTING")) {
            state = when (backend?.state?.value) {
                BackendState.READY -> "READY"
                BackendState.RECONNECTING -> "RECONNECTING"
                else -> "ERROR"
            }
            if (state == "ERROR") endpoint = null
        }
        val statistics = QwdttTelemetry.statistics.value
        val session = QwdttTelemetry.session.value
        val rawTor = tor.snapshot()
        val visibleTor = if (state == "STOPPED") rawTor + mapOf("percent" to 0, "stage" to "STOPPED")
            else if (state == "STARTING" && rawTor["state"] != "STARTING") rawTor + mapOf("percent" to 0, "stage" to "CONFIGURING")
            else rawTor
        val torStatus = visibleTor + mapOf("mode" to prefs.getString("torMode", "WEBTUNNEL"), "socksPort" to prefs.getInt("torPort", 19050))
        if (route == "TOR") {
            runCatching { NetworkDiagnostics.log.record(NetworkRoute.TOR, NetworkStage.valueOf(torStatus["stage"] as String), (torStatus["percent"] as? Int)?.coerceIn(0, 100)) }
        }
        return mapOf(
            "route" to route, "selected" to NetworkSelection.protected(route),
            "vkLoggedIn" to vkSession.loggedIn.value,
            "activeId" to if (route == "VK") profiles.activeId else null,
            "state" to state, "generation" to generation, "error" to publicError,
            "profiles" to metadata.get(), "tor" to torStatus, "captcha" to VkTransportCaptcha.pendingSnapshot(),
            "socks" to endpoint?.let { mapOf("port" to it.port, "username" to it.username, "password" to it.password) },
            "statistics" to mapOf("workers" to statistics.workers, "up" to statistics.upBytes, "down" to statistics.downBytes, "received" to statistics.received),
            "mode" to session.mode?.name, "dtls" to session.dtls,
            "events" to NetworkDiagnostics.log.events.value.map { mapOf("stage" to it.stage.name, "label" to it.stage.label, "progress" to it.progress, "route" to it.route.name) },
        )
    }
}
