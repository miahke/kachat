package com.panchat.qwdtt

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.panchat.tor.NativeTorManager
import org.torproject.arti.ArtiNative
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import java.io.File
import java.util.concurrent.TimeUnit

/** A clean emulator only. Live test requires explicit -e torLive true. No account boot. */
@RunWith(AndroidJUnit4::class)
class TorAndroidTest {
 private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
 @Test fun packagedTorAndPtLoadWithoutAccounts() {
  assertTrue(ArtiNative.getVersion().isNotBlank())
  val binary=File(context.applicationInfo.nativeLibraryDir,"libbitchat_pt.so")
  assertTrue(binary.canExecute())
  val process=ProcessBuilder(binary.absolutePath,"-version").redirectErrorStream(true).start()
  try { assertTrue(process.waitFor(10,TimeUnit.SECONDS));assertEquals(0,process.exitValue()) } finally {process.destroyForcibly()}
 }
 @Test fun liveTorBootstrapAndAuthenticatedHttps() {
  val args=InstrumentationRegistry.getArguments()
  assumeTrue(args.getString("torLive")=="true")
  val mode=args.getString("torMode") ?: "SNOWFLAKE"
  require(mode in setOf("SNOWFLAKE","DIRECT_TOR","WEBTUNNEL","OBFS4"))
  val bridgeText=if(mode in setOf("WEBTUNNEL","OBFS4")) File(context.noBackupFilesDir,"tor-test-bridges.txt").readText() else ""
  runBlocking {
   val manager=NativeTorManager(context)
   try {
    val endpoint=manager.start(bridgeText,mode,19060)
    assertEquals("READY",manager.snapshot()["state"])
    assertEquals(100,manager.snapshot()["percent"])
    val socket=Socket()
    socket.soTimeout=45000;socket.connect(InetSocketAddress("127.0.0.1",endpoint.port),5000)
    try {
     val input=DataInputStream(socket.getInputStream());val output=DataOutputStream(socket.getOutputStream())
     output.write(byteArrayOf(5,1,2));output.flush();assertEquals(5,input.readUnsignedByte());assertEquals(2,input.readUnsignedByte())
     val user=requireNotNull(endpoint.username).toByteArray();val password=requireNotNull(endpoint.password).toByteArray()
     output.writeByte(1);output.writeByte(user.size);output.write(user);output.writeByte(password.size);output.write(password);output.flush()
     assertEquals(1,input.readUnsignedByte());assertEquals(0,input.readUnsignedByte())
     val host="example.com".toByteArray()
     output.write(byteArrayOf(5,1,0,3));output.writeByte(host.size);output.write(host);output.writeShort(443);output.flush()
     assertEquals(5,input.readUnsignedByte());assertEquals(0,input.readUnsignedByte());input.readUnsignedByte()
     val size=when(input.readUnsignedByte()){1->4;3->input.readUnsignedByte();4->16;else->error("invalid SOCKS response")}
     input.readFully(ByteArray(size));input.readUnsignedShort()
     val tls=(SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(socket,"example.com",443,true) as SSLSocket
     tls.use {
      it.soTimeout=45000
      it.sslParameters=it.sslParameters.apply {endpointIdentificationAlgorithm="HTTPS"}
      it.startHandshake()
      it.outputStream.write("HEAD / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n".toByteArray());it.outputStream.flush()
      assertTrue(it.inputStream.bufferedReader().readLine().startsWith("HTTP/1."))
     }
    } finally {socket.close()}
   } finally {manager.stop()}
  }
 }
}
