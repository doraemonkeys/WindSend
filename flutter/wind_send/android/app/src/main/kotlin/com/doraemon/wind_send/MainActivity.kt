package com.doraemon.wind_send

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.plugin.common.MethodCall

class MainActivity: FlutterActivity() {
    private lateinit var filePickerHandler: FilePickerHandler
    private lateinit var clipboardHandler: ClipboardHandler
    private lateinit var uriRandomAccessHandler: UriRandomAccessHandler
    private lateinit var uriInfoHandler: UriInfoHandler

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        filePickerHandler = FilePickerHandler(this)
        clipboardHandler = ClipboardHandler(this)
        uriRandomAccessHandler = UriRandomAccessHandler(this)
        uriInfoHandler = UriInfoHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doraemon.wind_send/file_picker")
            .setMethodCallHandler { call, result -> 
                filePickerHandler.handleMethodCall(call, result) 
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doraemon.wind_send/clipboard")
            .setMethodCallHandler { call, result -> 
                clipboardHandler.handleMethodCall(call, result) 
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uri_random_access_reader")
            .setMethodCallHandler { call, result -> 
                uriRandomAccessHandler.handleMethodCall(call, result) 
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.doraemon.wind_send/uri")
            .setMethodCallHandler { call, result -> 
                uriInfoHandler.handleMethodCall(call, result) 
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        filePickerHandler.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        super.onDestroy()
        uriRandomAccessHandler.cleanup()
    }
}
