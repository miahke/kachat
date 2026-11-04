// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.content.Context
import android.content.Intent
import com.bitchat.android.net.route.*
import com.bitchat.android.net.importprofile.QwdttSubscriptionImport
import com.google.gson.Gson
import java.io.File
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.*

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
    private val metadata = QwdttProfileMetadataCache { profiles.load() }
    val vkSession by lazy { com.bitchat.android.net.vk.VkSessionRepository(NetworkSecretStore.create(context)) }
    private var backend: NetworkBackend? = null
    private var job: Job? = null
    private var generation = 0L
    @Volatile private var state = "STOPPED"
    @Volatile private var endpoint: SocksEndpoint? = null

    @Synchronized fun initialize(): Map<String, Any?> {
        val data = snapshot()
        if (profiles.selected && job == null) profiles.activeId?.let { connect(it) }
        return data
    }

    @Synchronized fun select() { profiles.selected = true }

    @Synchronized fun serviceDestroyed(epoch: Long) { if (generation == epoch) stop(false, stopService = false) }

    @Synchronized fun connect(id: String) {
        stop(false, stopService = false)
        profiles.selected = true
        val selected = profiles.load().first { it.profile.id == id }
        require(selected.secrets["vk-hash"].orEmpty().isNotBlank())
        require(selected.secrets["vk-password"].orEmpty().isNotBlank())
        profiles.activeId = id; profiles.selected = true
        val epoch = ++generation
        context.startForegroundService(Intent(context, QwdttService::class.java).putExtra("generation", epoch))
        val oldJob = job; oldJob?.cancel()
        endpoint = null; state = "STARTING"
        NetworkDiagnostics.log.clear(); NetworkDiagnostics.log.record(NetworkRoute.VK, NetworkStage.STARTING)
        job = scope.launch {
            oldJob?.join(); backend?.stop()
            try {
                val core = vkBackend(File(context.applicationInfo.nativeLibraryDir, "libbitchat_vk.so"),
                    File(context.noBackupFilesDir, "qwdtt")) { reference ->
                    selected.secrets[reference.substringAfter(':')]
                }
                backend = core
                val ready = core.start(selected.profile)
                synchronized(this@QwdttEngine) { if (generation == epoch) { endpoint = ready; state = "READY" } }
            } catch (cancel: CancellationException) { throw cancel }
            catch (_: Exception) {
                synchronized(this@QwdttEngine) {
                    if (generation == epoch) { endpoint = null; state = "ERROR" }
                }
            }
        }
    }

    @Synchronized fun stop(direct: Boolean, stopService: Boolean = true) {
        val epoch = ++generation; job?.cancel(); val previous = job; val previousBackend = backend
        endpoint = null; state = "STOPPED"
        if (direct) profiles.selected = false
        job = scope.launch {
            previous?.join(); previousBackend?.stop()
            synchronized(this@QwdttEngine) { if (generation == epoch && backend === previousBackend) backend = null }
        }
        NetworkDiagnostics.log.record(NetworkRoute.VK, NetworkStage.STOPPED)
        if (stopService) context.stopService(Intent(context, QwdttService::class.java))
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
        if (profiles.selected && profiles.activeId == profile.id) connect(profile.id)
    }

    @Synchronized fun delete(id: String) {
        if (profiles.activeId == id) { stop(false); profiles.activeId = null }
        profiles.save(profiles.load().filterNot { it.profile.id == id }); metadata.invalidate()
    }

    @Synchronized fun snapshot(): Map<String, Any?> {
        if (state == "READY" || state == "RECONNECTING") {
            state = when (backend?.state?.value) {
                BackendState.READY -> "READY"
                BackendState.RECONNECTING -> "RECONNECTING"
                else -> "ERROR"
            }
            if (state == "ERROR") endpoint = null
        }
        val statistics = QwdttTelemetry.statistics.value
        val session = QwdttTelemetry.session.value
        return mapOf(
            "vkLoggedIn" to vkSession.loggedIn.value, "selected" to profiles.selected, "activeId" to profiles.activeId, "state" to state, "generation" to generation,
            "profiles" to metadata.get(),
            "socks" to endpoint?.let { mapOf("port" to it.port, "username" to it.username, "password" to it.password) },
            "statistics" to mapOf("workers" to statistics.workers, "up" to statistics.upBytes, "down" to statistics.downBytes, "received" to statistics.received),
            "mode" to session.mode?.name, "dtls" to session.dtls,
            "events" to NetworkDiagnostics.log.events.value.map { mapOf("stage" to it.stage.name, "label" to it.stage.label) },
        )
    }
}
