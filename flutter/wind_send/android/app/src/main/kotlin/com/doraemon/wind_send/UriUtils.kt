package com.doraemon.wind_send

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import java.io.File

object UriUtils {
    private const val TAG = "WindSend_UriUtils"

    /**
     * Get real file path from URI with enhanced compatibility and error handling
     */
    fun getFilePathFromUri(context: Context, uri: Uri): String? {
        try {
            // 1. Handle DocumentProvider URIs
            if (DocumentsContract.isDocumentUri(context, uri)) {
                return handleDocumentUri(context, uri)
            }
            // 2. Handle content:// URIs (non-DocumentProvider)
            else if ("content".equals(uri.scheme, ignoreCase = true)) {
                return handleContentUri(context, uri)
            }
            // 3. Handle file:// URIs
            else if ("file".equals(uri.scheme, ignoreCase = true)) {
                return uri.path
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file path from URI: $uri", e)
        }
        return null
    }

    private fun handleDocumentUri(context: Context, uri: Uri): String? {
        return when {
            isExternalStorageDocument(uri) -> handleExternalStorageDocument(context, uri)
            isDownloadsDocument(uri) -> handleDownloadsDocument(context, uri)
            isMediaDocument(uri) -> handleMediaDocument(context, uri)
            else -> null
        }
    }

    private fun handleExternalStorageDocument(context: Context, uri: Uri): String? {
        val docId = DocumentsContract.getDocumentId(uri)
        val split = docId.split(":")
        
        if (split.isEmpty()) return null
        
        val type = split[0]
        
        return when {
            "primary".equals(type, ignoreCase = true) -> {
                if (split.size > 1) {
                    "${Environment.getExternalStorageDirectory()}/${split[1]}"
                } else {
                    Environment.getExternalStorageDirectory().toString()
                }
            }
            // Handle SD card and other external storage
            else -> {
                if (split.size > 1) {
                    val path = getPathFromExtSdCard(context, type, split[1])
                    if (path != null) {
                        Log.d(TAG, "Found SD card path: $path")
                    }
                    path
                } else {
                    null
                }
            }
        }
    }

    private fun handleDownloadsDocument(context: Context, uri: Uri): String? {
        val id = DocumentsContract.getDocumentId(uri)
        
        // Handle raw paths
        if (id.startsWith("raw:")) {
            return id.replaceFirst("raw:", "")
        }
        if (id.startsWith("/")) {
            return id
        }
        
        // Handle msf: prefix (Android 10+)
        if (id.startsWith("msf:")) {
            val split = id.split(":")
            if (split.size == 2) {
                val selection = "_id=?"
                val selectionArgs = arrayOf(split[1])

                // Try MediaStore.Downloads (API 29+)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    try {
                        val path = getDataColumn(
                            context,
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            selection,
                            selectionArgs
                        )
                        if (path != null) return path
                    } catch (e: Exception) {
                        Log.d(TAG, "Failed to query MediaStore.Downloads for msf id", e)
                    }
                }

                // Fallback to MediaStore.Files
                return getDataColumn(
                    context,
                    MediaStore.Files.getContentUri("external"),
                    selection,
                    selectionArgs
                )
            }
        }
        
        // Try to parse as Long ID
        var longId = id.toLongOrNull()
        if (longId == null && id.contains(":")) {
            longId = id.substringAfterLast(":").toLongOrNull()
        }

        if (longId != null) {
            // Try different download URIs
            val downloadUris = listOf(
                Uri.parse("content://downloads/public_downloads"),
                Uri.parse("content://downloads/my_downloads"),
                Uri.parse("content://downloads/all_downloads")
            )
            
            for (baseUri in downloadUris) {
                try {
                    val contentUri = ContentUris.withAppendedId(baseUri, longId)
                    val path = getDataColumn(context, contentUri, null, null)
                    if (path != null) {
                        Log.d(TAG, "Found download path using $baseUri: $path")
                        return path
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Failed to query $baseUri", e)
                }
            }
        }
        
        // Fallback: Try to get filename and construct path
        return try {
            getDataColumn(context, uri, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get path from downloads document", e)
            null
        }
    }

    private fun handleMediaDocument(context: Context, uri: Uri): String? {
        val docId = DocumentsContract.getDocumentId(uri)
        val split = docId.split(":")
        
        if (split.size < 2) return null
        
        val type = split[0]
        val id = split[1]
        
        val contentUri: Uri? = when (type) {
            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            "document" -> {
                // Some devices use "document" for files
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    MediaStore.Files.getContentUri("external")
                } else {
                    null
                }
            }
            else -> {
                Log.w(TAG, "Unknown media document type: $type")
                null
            }
        }
        
        return if (contentUri != null) {
            val selection = "_id=?"
            val selectionArgs = arrayOf(id)
            getDataColumn(context, contentUri, selection, selectionArgs)
        } else {
            null
        }
    }

    private fun handleContentUri(context: Context, uri: Uri): String? {
        // Google Photos and other cloud providers can't provide direct file paths
        if (isGooglePhotosUri(uri)) {
            Log.d(TAG, "Google Photos URI detected, direct path not available")
            return null
        }
        
        // Special handling for specific providers
        return when (uri.authority) {
            "com.google.android.apps.docs.storage" -> {
                Log.d(TAG, "Google Drive URI detected, direct path not available")
                null
            }
            "com.microsoft.skydrive.content.external" -> {
                Log.d(TAG, "OneDrive URI detected, direct path not available")
                null
            }
            else -> {
                getDataColumn(context, uri, null, null)
            }
        }
    }

    /**
     * Try to get path from SD card or other external storage
     */
    private fun getPathFromExtSdCard(context: Context, storageId: String, relativePath: String): String? {
        try {
            // Try to get external storage volumes (API 19+)
            val externalCacheDirs = context.externalCacheDirs
            for (file in externalCacheDirs) {
                if (file != null) {
                    val path = file.absolutePath
                    // Check if this matches the storage ID
                    if (path.contains(storageId, ignoreCase = true)) {
                        // Remove /Android/data/package/cache from the path
                        val basePath = path.substringBefore("/Android")
                        return "$basePath/$relativePath"
                    }
                }
            }
            
            // Fallback: Try common SD card mount points
            val possiblePaths = listOf(
                "/storage/$storageId/$relativePath",
                "/mnt/media_rw/$storageId/$relativePath",
                "/storage/sdcard1/$relativePath"
            )
            
            for (possiblePath in possiblePaths) {
                val file = File(possiblePath)
                if (file.exists()) {
                    return possiblePath
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting SD card path", e)
        }
        
        return null
    }

    /**
     * Query _data column from ContentResolver to get real file path
     */
    private fun getDataColumn(
        context: Context,
        uri: Uri?,
        selection: String?,
        selectionArgs: Array<String>?
    ): String? {
        var cursor: Cursor? = null
        val column = MediaStore.MediaColumns.DATA
        val projection = arrayOf(column)
        try {
            cursor = context.contentResolver.query(uri!!, projection, selection, selectionArgs, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndexOrThrow(column)
                return cursor.getString(index)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying data column", e)
        } finally {
            cursor?.close()
        }
        return null
    }

    // --- Helper Functions ---

    private fun isExternalStorageDocument(uri: Uri): Boolean {
        return "com.android.externalstorage.documents" == uri.authority
    }

    private fun isDownloadsDocument(uri: Uri): Boolean {
        return "com.android.providers.downloads.documents" == uri.authority
    }

    private fun isMediaDocument(uri: Uri): Boolean {
        return "com.android.providers.media.documents" == uri.authority
    }

    private fun isGooglePhotosUri(uri: Uri): Boolean {
        return "com.google.android.apps.photos.content" == uri.authority
    }
}

