// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

import com.google.gson.Gson

/** Cache only display metadata. Secret-bearing storage is loaded again to connect. */
class QwdttProfileMetadataCache(private val load: () -> List<StoredQwdtt>) {
    private val gson = Gson()
    private var cached: List<Map<String, Any?>>? = null
    @Synchronized fun invalidate() { cached = null }
    @Synchronized fun get(): List<Map<String, Any?>> = cached ?: load().map { row ->
        mapOf("profile" to (gson.fromJson(gson.toJson(row.profile), Map::class.java) + mapOf(
            "workers" to row.profile.workerCount,
            "hashCount" to row.secrets["vk-hash"].orEmpty().split(',').count { it.isNotBlank() })),
            "hasHash" to !row.secrets["vk-hash"].isNullOrBlank(),
            "hasPassword" to !row.secrets["vk-password"].isNullOrBlank())
    }.also { cached = it }
}
