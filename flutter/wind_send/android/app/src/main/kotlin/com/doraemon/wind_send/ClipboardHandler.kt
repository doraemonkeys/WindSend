package com.doraemon.wind_send

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ClipboardHandler(private val context: Context) {
    companion object {
        private const val CHANNEL = "com.doraemon.wind_send/clipboard"
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeFilePath" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "File path is null", null)
                    return
                }
                val error: String? = copyFileToClipboard(filePath)
                if (error != null) {
                    result.error("COPY_FILE_TO_CLIPBOARD_FAILED", error, null)
                } else {
                    result.success(null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun copyFileToClipboard(filePath: String): String? {
        try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val fileUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                File(filePath)
            )
            val clip = ClipData.newUri(context.contentResolver, "URI", fileUri)
            clipboard.setPrimaryClip(clip)
            return null
        } catch (e: Exception) {
            return e.message
        }
    }
}

