package com.doraemon.wind_send

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class UriRandomAccessHandler(private val context: Context) {
    companion object {
        private const val CHANNEL = "uri_random_access_reader"
    }

    private val nextId = AtomicInteger(1)
    // 创建一个绑定到主线程的协程作用域
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private data class OpenFile(
        val pfd: ParcelFileDescriptor,
        val stream: FileInputStream
    ) {
        val channel = stream.channel
    }

    private val openFiles = ConcurrentHashMap<Int, OpenFile>()

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> handleOpen(call, result)
            "read" -> handleRead(call, result)
            "close" -> handleClose(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleOpen(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr == null) {
            result.error("ARG_ERROR", "uri is required", null)
            return
        }

        try {
            val uri = Uri.parse(uriStr)
            val resolver = context.contentResolver
            val pfd = resolver.openFileDescriptor(uri, "r")

            if (pfd == null) {
                result.error("OPEN_FAILED", "openFileDescriptor returned null", null)
                return
            }

            val fis = FileInputStream(pfd.fileDescriptor)
            val openFile = OpenFile(pfd, fis)

            val id = nextId.getAndIncrement()
            openFiles[id] = openFile

            val length = openFile.channel.size()

            result.success(
                mapOf(
                    "id" to id,
                    "length" to length
                )
            )
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun handleRead(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id")
        val offset = call.argument<Long>("offset")
        val length = call.argument<Int>("length")

        if (id == null || offset == null || length == null) {
            result.error("ARG_ERROR", "id, offset, length are required", null)
            return
        }

        val openFile = openFiles[id]
        if (openFile == null) {
            result.error("INVALID_ID", "No open file for id $id", null)
            return
        }

        // 使用协程启动任务，默认在 Main 线程启动（因为 scope 是 Dispatchers.Main）
        scope.launch {
            try {
                // 切换到 IO 线程执行阻塞操作
                val bytes = withContext(Dispatchers.IO) {
                    val channel = openFile.channel
                    // Use positional read to be thread-safe and efficient
                    val fileSize = channel.size()

                    if (offset >= fileSize) {
                        return@withContext ByteArray(0)
                    }

                    val toRead = minOf(length.toLong(), fileSize - offset).toInt()
                    val buffer = ByteBuffer.allocate(toRead)

                    var total = 0
                    while (total < toRead) {
                        val read = channel.read(buffer, offset + total)
                        if (read <= 0) break
                        total += read
                    }

                    buffer.flip()
                    val res = ByteArray(buffer.remaining())
                    buffer.get(res)
                    res // 返回结果
                }
                
                // 自动切回主线程调用 result.success
                result.success(bytes)
            } catch (e: Exception) {
                e.printStackTrace()
                // 自动切回主线程调用 result.error
                result.error("READ_FAILED", e.message, null)
            }
        }
    }

    private fun handleClose(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id")
        if (id == null) {
            result.error("ARG_ERROR", "id is required", null)
            return
        }

        val openFile = openFiles.remove(id)
        if (openFile == null) {
            result.success(null)
            return
        }

        try {
            openFile.channel.close()
            openFile.stream.close()
            openFile.pfd.close()
            result.success(null)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("CLOSE_FAILED", e.message, null)
        }
    }

    fun cleanup() {
        scope.cancel() // 取消所有挂起的协程
        openFiles.values.forEach { openFile ->
            try {
                openFile.channel.close()
                openFile.stream.close()
                openFile.pfd.close()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        openFiles.clear()
    }
}
