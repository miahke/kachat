// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.bitchat.android.net.route.NetworkProfile
import com.bitchat.android.net.route.NetworkRoute
import com.google.gson.Gson
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class StoredQwdtt(val profile: NetworkProfile, val secrets: MutableMap<String, String>) {
    override fun toString() = "StoredQwdtt([redacted])"
}

class QwdttProfiles(context: Context) {
    private val prefs = context.getSharedPreferences("qwdtt_private", Context.MODE_PRIVATE)
    private val aad = "panchat-nym-qwdtt-profiles-v1".toByteArray()
    private val gson = Gson()
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("panchat-nym-qwdtt-v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("panchat-nym-qwdtt-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized fun load(): List<StoredQwdtt> {
        val value = prefs.getString("profiles", null) ?: return emptyList()
        require(value.length <= 262144)
        val record = Base64.getDecoder().decode(value)
        require(record.size >= 29)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, record.copyOfRange(0, 12)))
        cipher.updateAAD(aad)
        val plain = cipher.doFinal(record.copyOfRange(12, record.size))
        return try {
            gson.fromJson(plain.toString(Charsets.UTF_8), Array<StoredQwdtt>::class.java).toList().also { rows ->
                require(rows.size <= 32 && rows.map { it.profile.id }.distinct().size == rows.size)
                rows.forEach { require(it.profile.route == NetworkRoute.VK); it.profile.validate() }
            }
        } finally { plain.fill(0) }
    }
    @Synchronized fun save(rows: List<StoredQwdtt>) {
        require(rows.size <= 32)
        rows.forEach { require(it.profile.route == NetworkRoute.VK); it.profile.validate() }
        val plain = gson.toJson(rows).toByteArray()
        try {
            require(plain.size <= 196608)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key()); cipher.updateAAD(aad)
            check(prefs.edit().putString("profiles", Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(plain))).commit())
        } finally { plain.fill(0) }
    }
    var selected: Boolean
        get() = prefs.getBoolean("selected", false)
        set(value) { check(prefs.edit().putBoolean("selected", value).commit()) }
    var activeId: String?
        get() = prefs.getString("active", null)
        set(value) { check(prefs.edit().putString("active", value).commit()) }
}
