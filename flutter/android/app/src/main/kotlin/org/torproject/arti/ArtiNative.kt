package org.torproject.arti

/** JNI surface for the pinned, bundled Arti 1.9.0 core. */
@androidx.annotation.Keep
object ArtiNative {
    init { System.loadLibrary("arti_android") }
    external fun getVersion(): String
    external fun initialize(dataDir: String): Int
    external fun configureNetwork(bridges: String, program: String, username: String, password: String, certificateBundle: String): Int
    external fun isReady(): Int
    external fun getBootstrapProgress(): Int
    external fun startSocksProxy(port: Int): Int
    external fun stop(): Int
}
