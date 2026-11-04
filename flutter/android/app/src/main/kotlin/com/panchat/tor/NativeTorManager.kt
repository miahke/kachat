// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.tor

import android.content.Context
import com.bitchat.android.net.bridge.AndroidTrustBundle
import com.bitchat.android.net.bridge.BridgeParser
import com.bitchat.android.net.bridge.BridgeProtocol
import com.bitchat.android.net.route.SocksEndpoint
import kotlinx.coroutines.*
import org.torproject.arti.ArtiNative
import java.io.File
import java.security.SecureRandom
import java.util.Base64

/** One manager per application. The route owner serializes start/stop calls. */
class NativeTorManager(context: Context) {
    private val directory = File(context.noBackupFilesDir, "tor")
    private val program = File(context.applicationInfo.nativeLibraryDir, "libbitchat_pt.so")
    @Volatile private var status = Status("STOPPED", 0, "STOPPED", null)
    private data class Status(val state: String, val percent: Int, val stage: String, val error: String?)

    fun snapshot(): Map<String, Any?> {
        val s = status
        return mapOf("state" to s.state, "percent" to s.percent, "stage" to s.stage, "error" to s.error)
    }

    suspend fun start(bridgeText: String, mode: String, socksPort: Int = 19050): SocksEndpoint = withContext(Dispatchers.IO) {
        status = Status("STARTING", 0, "CONFIGURING", null)
        try {
            require(socksPort in 1024..65535)
            val bridges = TorConfiguration.bridgeLines(bridgeText, mode)
            check(directory.isDirectory || directory.mkdirs())
            val trust = if (bridges.isNotEmpty()) {
                check(program.isFile && program.canExecute())
                File(directory, "android-trust.pem").also {
                    AndroidTrustBundle.write(it, AndroidTrustBundle.systemCertificates())
                }.absolutePath
            } else ""
            val user = randomSecret()
            val password = randomSecret()
            check(ArtiNative.configureNetwork(bridges, program.absolutePath, user, password, trust) == 0)
            check(ArtiNative.initialize(directory.absolutePath) == 0)
            status = Status("STARTING", 0, "LISTENING", null)
            val listenResult = ArtiNative.startSocksProxy(socksPort)
            require(listenResult != -3) { "Local SOCKS port is unavailable" }
            check(listenResult == 0)
            withTimeout(240_000) {
                while (true) {
                    ensureActive()
                    val progress = ArtiNative.getBootstrapProgress()
                    check(progress in 0..100)
                    if (ArtiNative.isReady() == 1) {
                        // 100 is published only after the native core reports readiness.
                        status = Status("READY", progress, "READY", null)
                        break
                    }
                    status = Status("STARTING", progress.coerceAtMost(99), "BOOTSTRAPPING", null)
                    delay(250)
                }
            }
            SocksEndpoint(socksPort, user, password)
        } catch (e: Throwable) {
            runCatching { ArtiNative.stop() }
            val stage = when (e) {
                is TimeoutCancellationException -> "TIMEOUT"
                is CancellationException -> "STOPPED"
                is IllegalArgumentException -> "CONFIGURATION_ERROR"
                else -> "BOOTSTRAP_ERROR"
            }
            status = Status(if (stage == "STOPPED") "STOPPED" else "ERROR", status.percent.coerceAtMost(99), stage,
                if (stage == "STOPPED") null else stage)
            // Raw native errors may contain bridge addresses or URLs. Never forward them.
            if (e is CancellationException && e !is TimeoutCancellationException) throw e
            throw IllegalStateException(stage)
        }
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        try { ArtiNative.stop(); Unit } finally { status = Status("STOPPED", 0, "STOPPED", null) }
    }

    private fun randomSecret(): String = Base64.getUrlEncoder().withoutPadding()
        .encodeToString(ByteArray(24).also(SecureRandom()::nextBytes))
}

object TorConfiguration {
    // Official Tor Snowflake client example, verified 2026-11-04:
    // https://support.torproject.org/little-t-tor/circumvention/using-bridges/
    const val SNOWFLAKE_BRIDGE = "snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443 utls-imitate=hellorandomizedalpn"

    fun bridgeLines(text: String, mode: String): String {
        require(mode in setOf("DIRECT_TOR", "PLAIN_BRIDGES", "OBFS4", "WEBTUNNEL", "SNOWFLAKE"))
        if (mode == "DIRECT_TOR") return ""
        val expected = when (mode) {
            "PLAIN_BRIDGES" -> BridgeProtocol.PLAIN
            "OBFS4" -> BridgeProtocol.OBFS4
            "WEBTUNNEL" -> BridgeProtocol.WEBTUNNEL
            else -> BridgeProtocol.SNOWFLAKE
        }
        val lines = BridgeParser.parse(if (mode == "SNOWFLAKE" && text.isBlank()) SNOWFLAKE_BRIDGE else text)
        require(lines.isNotEmpty() && lines.all { it.protocol == expected })
        return lines.joinToString("\n") { it.toTorLine() }
    }
}
