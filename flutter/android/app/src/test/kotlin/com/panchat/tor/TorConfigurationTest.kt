package com.panchat.tor

import com.bitchat.android.net.bridge.BridgeParser
import com.bitchat.android.net.bridge.BridgeProtocol
import org.junit.Assert.*
import org.junit.Test

class TorConfigurationTest {
    private val fp = "0123456789ABCDEF0123456789ABCDEF01234567"
    @Test fun `plain bridge mode preserves real untransformed Tor bridge lines`() {
        assertEquals("192.0.2.1:443 $fp", TorConfiguration.bridgeLines("Bridge 192.0.2.1:443 $fp", "PLAIN_BRIDGES"))
    }
    @Test fun `snowflake builtin is parsed and preserved`() {
        val result = TorConfiguration.bridgeLines("", "SNOWFLAKE")
        assertEquals(BridgeProtocol.SNOWFLAKE, BridgeParser.parse(result).single().protocol)
        assertTrue(result.contains("fronts=www.cdn77.com,www.phpmyadmin.net"))
    }
    @Test fun `selected transport must have matching bridges`() {
        for (mode in listOf("PLAIN_BRIDGES", "OBFS4", "WEBTUNNEL")) {
            assertThrows(IllegalArgumentException::class.java) { TorConfiguration.bridgeLines("", mode) }
            assertThrows(IllegalArgumentException::class.java) { TorConfiguration.bridgeLines(TorConfiguration.SNOWFLAKE_BRIDGE, mode) }
        }
        assertEquals("", TorConfiguration.bridgeLines("unused", "DIRECT_TOR"))
    }
    @Test fun `control characters and unsupported transport options never escape validation`() {
        for (line in listOf(
            "webtunnel 192.0.2.1:443 $fp url=https://private.invalid/path\u0000",
            "snowflake 192.0.2.3:80 $fp url=http://private.invalid ice=stun:example.invalid:1",
            "snowflake 192.0.2.3:80 $fp url=https://private.invalid ice=stun:example.invalid:1 proxy=socks5://private.invalid",
            "snowflake 192.0.2.3:80 $fp url=https://private.invalid ice=stun:example.invalid:1 fingerprint=1111111111111111111111111111111111111111"
        )) {
            val ex = assertThrows(IllegalArgumentException::class.java) { BridgeParser.parse(line) }
            assertFalse(ex.message.orEmpty().contains("private.invalid"))
        }
    }
}
