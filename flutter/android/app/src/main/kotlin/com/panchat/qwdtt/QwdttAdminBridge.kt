// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.content.Context
import com.bitchat.android.net.deploy.*
import java.io.File
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Explicit SSH administration only; passwords/keys live for one request, never in profiles. */
class QwdttAdminBridge(private val context: Context) {
    private val mutex = Mutex()
    suspend fun execute(method: String, input: Map<*, *>): Any = mutex.withLock {
        fun text(key: String) = (input[key] as? String).orEmpty()
        val target = PreparationTarget(text("host"), (input["port"] as? Number)?.toInt() ?: 22,
            if (method == "sshProbe") "" else text("fingerprint"), text("username").ifEmpty { "root" })
        withPreparationConnection { connection ->
            if (method == "sshProbe") return@withPreparationConnection connection.probe(target)
            require(target.fingerprint.isNotBlank())
            val authentication = if (text("key").isNotEmpty()) PreparationAuthentication.PrivateKey(
                text("key").toByteArray(), text("passphrase").toByteArray())
                else PreparationAuthentication.Password(text("password").toByteArray())
            connection.connect(target, authentication)
            if (method == "sshDeploy") {
                val directory = File(context.cacheDir, "qwdtt-kit-${UUID.randomUUID()}")
                check(directory.mkdir())
                try {
                    val checksum = context.assets.open("network/panchan-deployer.sha256").bufferedReader().use { it.readText().trim().split(Regex("\\s+"))[0] }
                    val kit = context.assets.open("network/panchan-deployer.zip").use { PreparationKit.read(it, checksum, directory) }
                    ServerPreparation.run(connection, kit) { /* Whitelisted steps only; no remote stdout is logged. */ }
                    mapOf("deployed" to true)
                } finally { directory.deleteRecursively() }
            } else {
                require(method == "sshAdmin")
                val fields = (input["fields"] as? Map<*, *>)?.entries?.associate { (k, v) -> require(k is String && v is String); k to v } ?: emptyMap()
                QwdttAdministration.execute(connection, QwdttAdminRequest(text("action"), fields))
                val list = QwdttAdministration.execute(connection, QwdttAdminRequest("list"))
                mapOf("access" to QwdttAdministration.parse(list).map { row -> mapOf(
                    "label" to row.label, "password" to row.password, "devices" to row.devices,
                    "expiresAt" to row.expiresAt, "revoked" to row.revoked,
                    "up" to row.sent, "down" to row.received, "subscription" to row.subscription(target.host)) })
            }
        }
    }
}
