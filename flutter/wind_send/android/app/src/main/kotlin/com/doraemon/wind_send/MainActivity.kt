package com.doraemon.wind_send

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.app.Activity
import android.net.Uri
import android.provider.MediaStore
import android.content.ContentResolver
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import java.io.File
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.FileProvider


class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.doraemon.wind_send/file_picker"
    private val CHANNEL_CLIPBOARD = "com.doraemon.wind_send/clipboard"
    private val REQUEST_CODE_PICK_FILES = 1001
    private val REQUEST_CODE_PICK_FOLDER = 1002
    private var packageNameToLaunch: String? = null
    private var resultCallback: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    packageNameToLaunch = call.argument<String>("packageName")
                    resultCallback = result
                    launchFileManager()
                }
                "pickFolder" -> {
                    packageNameToLaunch = call.argument<String>("packageName")
                    resultCallback = result
                    launchFolderPicker()
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CLIPBOARD).setMethodCallHandler { call, result ->
            when (call.method) {
                "writeFilePath" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                       result.error("INVALID_ARGUMENT", "File path is null", null)
                       return@setMethodCallHandler
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
    }

    private fun launchFileManager() {
        packageNameToLaunch?.let { pkgName ->
            val intent = Intent(Intent.ACTION_GET_CONTENT)
            intent.type = "*/*"
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            intent.setPackage(pkgName)

            if (intent.resolveActivity(packageManager) != null) {
                startActivityForResult(intent, REQUEST_CODE_PICK_FILES)
            } else {
                resultCallback?.error("UNAVAILABLE", "File manager not found", null)
            }
        } ?: run {
            resultCallback?.error("INVALID_ARGUMENT", "Package name is null", null)
        }
    }

    private fun copyFileToClipboard(filePath: String): String? {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val fileUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", File(filePath))
            val clip = ClipData.newUri(contentResolver, "URI", fileUri)
            clipboard.setPrimaryClip(clip)
            return null
        } catch (e: Exception) {
            return e.message
        }
    }

    private fun copyFileToClipboardIntent(filePath: String): String? {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        
        val clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newUri(contentResolver, "File", uri)
        clipboardManager.setPrimaryClip(clip)

        val intent = Intent(Intent.ACTION_SEND)
        intent.type = contentResolver.getType(uri)
        intent.putExtra(Intent.EXTRA_STREAM, uri)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        
        return null
    }

    private fun launchFolderPicker() {
        packageNameToLaunch?.let { pkgName ->
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.setPackage(pkgName)

            if (intent.resolveActivity(packageManager) != null) {
                startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
            } else {
                resultCallback?.error("UNAVAILABLE", "Folder picker not found", null)
            }
        } ?: run {
            resultCallback?.error("INVALID_ARGUMENT", "Package name is null", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_CODE_PICK_FILES -> handleFilePickerResult(resultCode, data)
            REQUEST_CODE_PICK_FOLDER -> handleFolderPickerResult(resultCode, data)
        }
    }

    private fun handleFilePickerResult(resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK) {
            val fileUris = mutableListOf<String>()

            if (data?.clipData != null) {
                val count = data.clipData!!.itemCount
                for (i in 0 until count) {
                    data.clipData!!.getItemAt(i).uri?.let { uri ->
                        fileUris.add(getFilePathFromUri(uri))
                    }
                }
            } else {
                data?.data?.let { uri ->
                    fileUris.add(getFilePathFromUri(uri))
                }
            }

            resultCallback?.success(fileUris)
        } else {
            resultCallback?.success(emptyList<String>())
        }
    }

    private fun handleFolderPickerResult(resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK) {
            data?.data?.let { uri ->
                val folderPath = getFilePathFromUri(uri)
                resultCallback?.success(folderPath)
            } ?: run {
                resultCallback?.error("NO_FOLDER_SELECTED", "No folder was selected", null)
            }
        } else {
            resultCallback?.success(null)
        }
    }

    private fun getFilePathFromUri(uri: Uri): String {
        // 实现Uri到文件路径的转换
        // 注意：在Android 10及以上版本，直接获取文件路径可能会有问题
        // 你可能需要使用ContentResolver和DocumentFile来处理文件
        val projection = arrayOf(MediaStore.Images.Media.DATA)
        val cursor = contentResolver.query(uri, projection, null, null, null)
        val columnIndex = cursor?.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
        cursor?.moveToFirst()
        val path = cursor?.getString(columnIndex ?: 0)
        cursor?.close()
        return path ?: uri.toString()
    }
}
