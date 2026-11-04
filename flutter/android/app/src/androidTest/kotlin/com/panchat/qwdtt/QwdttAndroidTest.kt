// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bitchat.android.net.route.*
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic profiles only, no account boot, VK requests or external packets. */
@RunWith(AndroidJUnit4::class)
class QwdttAndroidTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun profileSecretsUseKeystoreAndSelectionSurvivesRecreation() {
        val prefs = context.getSharedPreferences("qwdtt_private", 0)
        prefs.edit().clear().commit()
        try {
            val store = QwdttProfiles(context)
            val profile = NetworkProfile(id = "synthetic_profile", route = NetworkRoute.VK, serverHost = "server.example.invalid")
            store.save(listOf(StoredQwdtt(profile, mutableMapOf("vk-password" to "synthetic_password_value", "vk-hash" to "synthetic_hash_value_123456"))))
            store.selected = true; store.activeId = profile.id
            assertFalse(prefs.getString("profiles", "")!!.contains("synthetic_password_value"))
            assertFalse(prefs.getString("profiles", "")!!.contains("synthetic_hash_value_123456"))
            val restored = QwdttProfiles(context)
            assertTrue(restored.selected); assertEquals(profile.id, restored.activeId)
            assertEquals("synthetic_password_value", restored.load().single().secrets["vk-password"])
            prefs.edit().putString("profiles", "invalid").commit()
            assertTrue(runCatching { restored.load() }.isFailure)
        } finally { prefs.edit().clear().commit() }
    }

    @Test fun packagedCoreIsExecutableAndRejectsInvalidConfigBeforeNetworking() {
        val executable = File(context.applicationInfo.nativeLibraryDir, "libbitchat_vk.so")
        assertTrue(executable.isFile); assertTrue(executable.canExecute())
        val process = ProcessBuilder(executable.absolutePath).redirectErrorStream(true).start()
        try {
            process.outputStream.use { it.write("{}\n".toByteArray()); it.flush() }
            assertTrue(process.waitFor(10, TimeUnit.SECONDS))
            assertEquals(2, process.exitValue())
            assertEquals("ERROR configuration", process.inputStream.bufferedReader().readText().trim())
        } finally { process.destroyForcibly() }
    }
}
