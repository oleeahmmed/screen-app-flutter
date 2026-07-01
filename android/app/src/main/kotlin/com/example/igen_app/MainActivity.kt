package com.example.igen_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestScreenCapturePermission(result)
                    "isPermissionGranted" -> result.success(ScreenshotCaptureHelper.hasProjection())
                    "capture" -> captureOnBackground(result)
                    "startForeground" -> {
                        MonitorForegroundService.start(applicationContext)
                        result.success(true)
                    }
                    "stopForeground" -> {
                        MonitorForegroundService.stop(applicationContext)
                        result.success(true)
                    }
                    "releaseProjection" -> {
                        ScreenshotCaptureHelper.release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun captureOnBackground(result: MethodChannel.Result) {
        Thread {
            try {
                val bytes = ScreenshotCaptureHelper.captureJpeg(applicationContext, 70)
                runOnUiThread {
                    if (bytes != null && bytes.isNotEmpty()) {
                        result.success(bytes)
                    } else {
                        result.error("CAPTURE_FAILED", "Empty screenshot", null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("CAPTURE_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun requestScreenCapturePermission(result: MethodChannel.Result) {
        if (ScreenshotCaptureHelper.hasProjection()) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_MEDIA_PROJECTION) return

        val callback = pendingPermissionResult
        pendingPermissionResult = null

        if (resultCode == Activity.RESULT_OK && data != null) {
            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = mgr.getMediaProjection(resultCode, data)
            if (projection != null) {
                ScreenshotCaptureHelper.setMediaProjection(projection)
                callback?.success(true)
            } else {
                callback?.success(false)
            }
        } else {
            callback?.success(false)
        }
    }

    companion object {
        const val SCREENSHOT_CHANNEL = "com.example.igen_app/screenshot"
        private const val REQUEST_MEDIA_PROJECTION = 9914
    }
}
