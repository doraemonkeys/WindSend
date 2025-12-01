package com.doraemon.wind_send

import android.app.Activity
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.net.toUri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UriInfoHandler(private val activity: Activity) {
    companion object {
        private const val CHANNEL = "com.doraemon.wind_send/uri"
        private const val TAG = "WindSend_UriInfo"
    }

    private data class FileInfo(
        val fileName: String?,
        val size: Long,
        val mimeType: String?,
        val lastModified: Long?
    )

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getFileInfo" -> getFileInfoFromUri(call, result)
            "getFilePath" -> getFilePath(call, result)
            else -> result.notImplemented()
        }
    }

    private fun getFilePath(call: MethodCall, result: MethodChannel.Result) {
        val args: Map<String, Any> = call.arguments as? Map<String, Any> ?: mapOf()
        val uriString = args["uri"] as? String

        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "URI string is null or empty", null)
            return
        }

        try {
            val uri = uriString.toUri()
            Log.d(TAG, "Getting file path from URI: $uri (scheme: ${uri.scheme})")

            val filePath = UriUtils.getFilePathFromUri(activity, uri)
            result.success(mapOf("path" to filePath))
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception accessing URI: $uriString", e)
            result.error("PERMISSION_DENIED", "No permission to access this URI: ${e.message}", null)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Invalid URI format: $uriString", e)
            result.error("INVALID_URI", "Invalid URI format: ${e.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file path from URI: $uriString", e)
            result.error("ERROR", "Error getting file path: ${e.message}", null)
        }
    }

    private fun getFileInfoFromUri(call: MethodCall, result: MethodChannel.Result) {
        val args: Map<String, Any> = call.arguments as? Map<String, Any> ?: mapOf()
        val uriString = args["uri"] as? String

        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "URI string is null or empty", null)
            return
        }

        try {
            val uri = uriString.toUri()
            Log.d(TAG, "Getting file info from URI: $uri (scheme: ${uri.scheme})")

            val fileInfo = when {
                "content".equals(uri.scheme, ignoreCase = true) -> getFileInfoFromContentUri(uri)
                "file".equals(uri.scheme, ignoreCase = true) -> getFileInfoFromFileUri(uri)
                else -> {
                    Log.w(TAG, "Unsupported URI scheme: ${uri.scheme}")
                    null
                }
            }

            val finalInfo = fileInfo ?: getFileInfoFromDocumentFile(uri)

            if (finalInfo != null) {
                val filePath = UriUtils.getFilePathFromUri(activity, uri)

                result.success(
                    mapOf(
                        "fileName" to finalInfo.fileName,
                        "size" to finalInfo.size,
                        "path" to filePath,
                        "mimeType" to finalInfo.mimeType,
                        "lastModified" to finalInfo.lastModified
                    )
                )
                Log.d(TAG, "Successfully retrieved file info: ${finalInfo.fileName}, size: ${finalInfo.size}")
            } else {
                Log.w(TAG, "Could not retrieve file info from URI: $uri")
                result.success(null)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception accessing URI: $uriString", e)
            result.error("PERMISSION_DENIED", "No permission to access this URI: ${e.message}", null)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Invalid URI format: $uriString", e)
            result.error("INVALID_URI", "Invalid URI format: ${e.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file info from URI: $uriString", e)
            result.success(null)
        }
    }

    private fun getFileInfoFromContentUri(uri: Uri): FileInfo? {
        return try {
            val contentResolver = activity.contentResolver
            var fileName: String? = null
            var size: Long = -1L
            var mimeType: String? = null
            var lastModified: Long? = null

            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val displayNameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (displayNameIndex != -1 && !cursor.isNull(displayNameIndex)) {
                        fileName = cursor.getString(displayNameIndex)
                    }

                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }

                    val lastModifiedIndex =
                        cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (lastModifiedIndex != -1 && !cursor.isNull(lastModifiedIndex)) {
                        lastModified = cursor.getLong(lastModifiedIndex)
                    }
                }
            }

            mimeType = contentResolver.getType(uri)

            if (fileName != null || size != -1L) {
                FileInfo(fileName, size, mimeType, lastModified)
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file info from content URI", e)
            null
        }
    }

    private fun getFileInfoFromFileUri(uri: Uri): FileInfo? {
        return try {
            val filePath = uri.path ?: return null
            val file = File(filePath)

            if (!file.exists()) {
                Log.w(TAG, "File does not exist: $filePath")
                return null
            }

            val fileName = file.name
            val size = file.length()
            val lastModified = file.lastModified()

            val mimeType = activity.contentResolver?.getType(uri)

            FileInfo(fileName, size, mimeType, lastModified)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file info from file URI", e)
            null
        }
    }

    private fun getFileInfoFromDocumentFile(uri: Uri): FileInfo? {
        return try {
            val documentFile = DocumentFile.fromSingleUri(activity, uri) ?: return null

            if (!documentFile.exists()) {
                Log.w(TAG, "Document file does not exist")
                return null
            }

            val fileName = documentFile.name
            val size = documentFile.length()
            val mimeType = documentFile.type
            val lastModified = documentFile.lastModified()

            FileInfo(fileName, size, mimeType, lastModified)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file info from DocumentFile", e)
            null
        }
    }
}

