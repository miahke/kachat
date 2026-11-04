package com.bitchat.android.net

import com.bitchat.android.net.importprofile.QwdttSubscriptionImport
import com.bitchat.android.net.route.*
import org.junit.Assert.*
import org.junit.Test

class QwdttSettingsTest {
    @Test fun `legacy saved profiles without workers retain two channels`() {
        val gson = com.google.gson.Gson()
        val json = gson.toJsonTree(NetworkProfile(route = NetworkRoute.VK, serverHost = "server.example.invalid")).asJsonObject
        json.remove("workers")
        val legacy = gson.fromJson(json, NetworkProfile::class.java)
        assertEquals(2, legacy.workerCount)
        val restored = QwdttSubscriptionImport.parse(QwdttSubscriptionImport.export(legacy, "synthetic-password", "synthetic_hash_123456789")).single()
        assertEquals(2, restored.profile.workerCount)
    }

    @Test
    fun `sharing round trips supported transport settings and excludes local identity`() {
        val profile =
            NetworkProfile(
                name = "Synthetic & русский",
                route = NetworkRoute.VK,
                serverHost = "2001:db8::1",
                serverPort = 56002,
                socksPort = 9000,
                username = "local",
                vkMode = VkMode.WG,
                turnHost = "turn.example.invalid",
                turnPort = 3478,
                turnTcp = false,
                noDtls = true,
                autoPeerMode = false,
                fallbackPort = 56004,
                connectTimeoutSeconds = 120,
                handshakeTimeoutSeconds = 25,
                configTimeoutSeconds = 30,
                tunnelDns = "1.1.1.1,8.8.8.8",
                tunnelMtu = 1280,
                wgKeepaliveSeconds = 20,
                dns = "doh:https://dns.example.invalid/dns-query",
                obfuscation = "video",
                vkAnonPath = "legacy",
                workers = 81,
            )
        val uri =
            QwdttSubscriptionImport.export(
                profile,
                "synthetic&password",
                "synthetic_hash_123456789,synthetic_hash_987654321",
            )
        assertFalse(uri.contains(profile.id))
        assertFalse(uri.contains(profile.deviceId))
        val imported = QwdttSubscriptionImport.parse(uri).single()
        assertEquals(
            profile.copy(id = imported.profile.id, deviceId = imported.profile.deviceId),
            imported.profile,
        )
        assertEquals("synthetic&password", imported.secrets["vk-password"])
        assertEquals("synthetic_hash_123456789,synthetic_hash_987654321", imported.secrets["vk-hash"])
        assertEquals(81, imported.profile.workerCount)
    }

    @Test
    fun `newlines split hashes as in upstream export`() {
        val profiles =
            QwdttSubscriptionImport.parse(
                """{"peer":"server.example.invalid","password":"synthetic","hashes":"first_hash_123456\nsecond_hash_123456"}"""
            )
        assertEquals(1, profiles.size)
        assertEquals("first_hash_123456,second_hash_123456", profiles.single().secrets["vk-hash"])
    }

    @Test
    fun `invalid advanced configuration fails before connection`() {
        val profile = NetworkProfile(route = NetworkRoute.VK, serverHost = "server.example.invalid")
        for (invalid in
            listOf(
                profile.copy(serverHost = "https://server.example.invalid"),
                profile.copy(serverHost = "server.example.invalid:56000"),
                profile.copy(turnHost = "host/path"),
                profile.copy(dns = "typo-cloudflare"),
                profile.copy(dns = "custom:"),
                profile.copy(dns = "custom:999.1.1.1"),
                profile.copy(dns = "doh:http://dns.example.invalid/query"),
                profile.copy(dns = "doh:https://user:secret@dns.example.invalid/query"),
                profile.copy(tunnelMtu = 575),
                profile.copy(wgKeepaliveSeconds = 121),
                profile.copy(handshakeTimeoutSeconds = 61),
                profile.copy(obfuscation = "unknown"),
                profile.copy(vkAnonPath = "unknown"),
            )) assertThrows(IllegalArgumentException::class.java) { invalid.validate() }
        for (dns in
            listOf(
                "yandex",
                "cloudflare",
                "google",
                "doh-yandex",
                "doh-cloudflare",
                "doh-google",
                "custom:1.1.1.1:5353,8.8.8.8",
                "doh:https://dns.example.invalid/query",
            )) {
            profile.copy(dns = dns).validate()
        }
    }

    @Test
    fun `strict imported booleans prevent silently replacing intended transport`() {
        assertThrows(Exception::class.java) {
            QwdttSubscriptionImport.parse(
                "qwdtt://config?peer=server.example.invalid&pass=synthetic&turnTcp=treu"
            )
        }
        val profile =
            QwdttSubscriptionImport.parse(
                    "qwdtt://config?peer=server.example.invalid&pass=synthetic&noDtls=true"
                )
                .single()
                .profile
        assertEquals(56002, profile.serverPort)
    }
}
