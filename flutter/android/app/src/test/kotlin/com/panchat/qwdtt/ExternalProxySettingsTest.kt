package com.panchat.qwdtt
import org.junit.Assert.*
import org.junit.Test

class ExternalProxySettingsTest {
 @Test fun validatesOptionalAuthAndProtectsExternalRoute() {
  val value=ExternalProxySettings.validate(mapOf("type" to "HTTPS","host" to "proxy.example","port" to 443))
  assertEquals("",value["username"])
  assertEquals("PROXY",NetworkSelection.resolve("PROXY",false))
  assertTrue(NetworkSelection.protected("PROXY"))
 }
 @Test fun rejectsBadPortsProtocolsAndHeaderInjection() {
  val base=mapOf("type" to "SOCKS5","host" to "proxy.example","port" to 1080)
  for (override in listOf(mapOf("port" to 0),mapOf("port" to 443.5),mapOf("host" to "host\r\nheader"),mapOf("type" to "MTProto"),mapOf("username" to "user\n"))) {
   try {ExternalProxySettings.validate(base+override);fail("invalid proxy accepted")} catch (_:IllegalArgumentException) {}
  }
 }
}
