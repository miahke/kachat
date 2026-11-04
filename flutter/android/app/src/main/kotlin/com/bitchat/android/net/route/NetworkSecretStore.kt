// SPDX-License-Identifier: AGPL-3.0-only
package com.bitchat.android.net.route

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class NetworkSecretStore private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("qwdtt_vk_session", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("panchat-nym-vk-v1", null) as? SecretKey) ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("panchat-nym-vk-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes("GCM").setEncryptionPaddings("NoPadding").build())
        }.generateKey()
    }
    @Synchronized fun get(id: String): String? {
        require(id.length in 1..128)
        val value = prefs.getString(id, null) ?: return null
        require(value.length <= 131072)
        val bytes = Base64.getDecoder().decode(value); require(bytes.size >= 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(id.toByteArray())
        val plain = cipher.doFinal(bytes.copyOfRange(12, bytes.size))
        return try { plain.toString(Charsets.UTF_8) } finally { plain.fill(0) }
    }
    @Synchronized fun put(id: String, value: String) {
        require(id.length in 1..128 && value.length <= 65536)
        val plain = value.toByteArray()
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key()); cipher.updateAAD(id.toByteArray())
            check(prefs.edit().putString(id, Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(plain))).commit())
        } finally { plain.fill(0) }
    }
    @Synchronized fun remove(id: String) { check(prefs.edit().remove(id).commit()) }
    companion object { fun create(context: Context) = NetworkSecretStore(context.applicationContext) }
}
