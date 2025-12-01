package com.doraemon.wind_send

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class FilePickerHandler(private val activity: Activity) : PluginRegistry.ActivityResultListener {
    companion object {
        private const val CHANNEL = "com.doraemon.wind_send/file_picker"
        const val REQUEST_CODE_PICK_FILES = 1001
        const val REQUEST_CODE_PICK_FOLDER = 1002
    }

    private var packageNameToLaunch: String? = null
    private var resultCallback: MethodChannel.Result? = null

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

    private fun launchFileManager() {
        packageNameToLaunch?.let { pkgName ->
            val intent = Intent(Intent.ACTION_GET_CONTENT)
            intent.type = "*/*"
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            intent.addCategory(Intent.CATEGORY_OPENABLE)
            intent.setPackage(pkgName)

            if (intent.resolveActivity(activity.packageManager) != null) {
                activity.startActivityForResult(intent, REQUEST_CODE_PICK_FILES)
            } else {
                resultCallback?.error("UNAVAILABLE", "File manager not found", null)
            }
        } ?: run {
            resultCallback?.error("INVALID_ARGUMENT", "Package name is null", null)
        }
    }

    private fun launchFolderPicker() {
        packageNameToLaunch?.let { pkgName ->
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.addCategory(Intent.CATEGORY_DEFAULT)
            intent.setPackage(pkgName)

            if (intent.resolveActivity(activity.packageManager) != null) {
                activity.startActivityForResult(intent, REQUEST_CODE_PICK_FOLDER)
            } else {
                resultCallback?.error("UNAVAILABLE", "Folder picker not found", null)
            }
        } ?: run {
            resultCallback?.error("INVALID_ARGUMENT", "Package name is null", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQUEST_CODE_PICK_FILES -> {
                handleFilePickerResult(resultCode, data)
                return true
            }
            REQUEST_CODE_PICK_FOLDER -> {
                handleFolderPickerResult(resultCode, data)
                return true
            }
        }
        return false
    }

    private fun handleFilePickerResult(resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK) {
            val fileUris = mutableListOf<String>()

            if (data?.clipData != null) {
                val count = data.clipData!!.itemCount
                for (i in 0 until count) {
                    data.clipData!!.getItemAt(i).uri?.let { uri ->
                        fileUris.add(UriUtils.getFilePathFromUri(activity, uri) ?: uri.toString())
                    }
                }
            } else {
                data?.data?.let { uri ->
                    fileUris.add(UriUtils.getFilePathFromUri(activity, uri) ?: uri.toString())
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
                val folderPath = UriUtils.getFilePathFromUri(activity, uri) ?: uri.toString()
                resultCallback?.success(folderPath)
            } ?: run {
                resultCallback?.error("NO_FOLDER_SELECTED", "No folder was selected", null)
            }
        } else {
            resultCallback?.success(null)
        }
    }

}

