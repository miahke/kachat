package com.panchat.qwdtt
import com.bitchat.android.net.route.*
import org.junit.Assert.*
import org.junit.Test
class QwdttProfileMetadataCacheTest {
 @Test fun repeatedPollsLoadEncryptedStorageOnlyOnceAndNeverCacheSecrets() {
  var calls=0
  val cache=QwdttProfileMetadataCache { calls++; listOf(StoredQwdtt(NetworkProfile(route=NetworkRoute.VK),mutableMapOf("vk-password" to "secret-value-not-for-metadata","vk-hash" to "secret-hash-not-for-metadata"))) }
  repeat(100){cache.get()}
  assertEquals(1,calls)
  assertFalse(cache.get().toString().contains("secret-value"))
  assertFalse(cache.get().toString().contains("secret-hash"))
  cache.invalidate();cache.get();assertEquals(2,calls)
 }
 @Test fun failedLoadIsNotCached() {
  var calls=0
  val cache=QwdttProfileMetadataCache { calls++; if(calls==1) error("synthetic storage failure") else emptyList() }
  assertTrue(runCatching {cache.get()}.isFailure);assertTrue(cache.get().isEmpty());assertEquals(2,calls)
 }
}
