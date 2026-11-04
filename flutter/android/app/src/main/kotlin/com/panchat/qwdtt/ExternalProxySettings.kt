// SPDX-License-Identifier: AGPL-3.0-only
package com.panchat.qwdtt

object ExternalProxySettings {
    fun validate(raw: Map<*, *>): Map<String, Any> {
        val type = raw["type"] as? String ?: error("Proxy type required")
        val host = raw["host"] as? String ?: ""
        val number = raw["port"] as? Number ?: error("Proxy port required")
        val port = number.toInt()
        val user = raw["username"] as? String ?: ""
        val password = raw["password"] as? String ?: ""
        require(type in setOf("HTTP", "HTTPS", "SOCKS5"))
        require(host.length in 1..253 && host.matches(Regex("[A-Za-z0-9.:%_-]+")))
        require(port in 1..65535 && number.toDouble() == port.toDouble())
        require(user.toByteArray(Charsets.UTF_8).size <= 255 && password.toByteArray(Charsets.UTF_8).size <= 255)
        require(':' !in user && (user.isNotEmpty() || password.isEmpty()))
        require((user + password).none { it.isISOControl() })
        return mapOf("type" to type, "host" to host, "port" to port, "username" to user, "password" to password)
    }
}
