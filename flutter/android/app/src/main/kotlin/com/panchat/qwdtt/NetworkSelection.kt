// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

/** Missing old preferences migrate; corrupt/new unknown selections stay blocked. */
object NetworkSelection {
    fun resolve(saved: String?, legacySelected: Boolean): String = when (saved) {
        null -> if (legacySelected) "VK" else "DIRECT"
        "DIRECT", "VK", "TOR", "PROXY" -> saved
        else -> "BLOCKED"
    }
    fun protected(route: String): Boolean = route != "DIRECT"
}
