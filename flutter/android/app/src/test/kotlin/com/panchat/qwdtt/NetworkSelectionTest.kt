package com.panchat.qwdtt
import org.junit.Assert.*
import org.junit.Test
class NetworkSelectionTest {
 @Test fun oldProtectedSelectionMigratesToVkWithoutDirectFallback() {
  assertEquals("VK",NetworkSelection.resolve(null,true))
  assertEquals("DIRECT",NetworkSelection.resolve(null,false))
 }
 @Test fun invalidPreferenceRemainsBlockedAndTorOverridesOldVkFlag() {
  val corrupt=NetworkSelection.resolve("unknown",false)
  assertEquals("BLOCKED",corrupt);assertTrue(NetworkSelection.protected(corrupt))
  assertEquals("TOR",NetworkSelection.resolve("TOR",true))
  assertTrue(NetworkSelection.protected("TOR"))
 }
}
