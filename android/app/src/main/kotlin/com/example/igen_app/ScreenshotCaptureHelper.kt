package com.example.igen_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object ScreenshotCaptureHelper {
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var width = 0
    private var height = 0
    private var density = 0

    fun setMediaProjection(projection: MediaProjection) {
        releaseVirtualDisplay()
        mediaProjection = projection
        projection.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    release()
                }
            },
            Handler(Looper.getMainLooper()),
        )
    }

    fun hasProjection(): Boolean = mediaProjection != null

    fun release() {
        releaseVirtualDisplay()
        mediaProjection?.stop()
        mediaProjection = null
    }

    private fun releaseVirtualDisplay() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
    }

    private fun ensureVirtualDisplay(context: Context) {
        val projection = mediaProjection ?: throw IllegalStateException("MediaProjection not granted")
        if (virtualDisplay != null && imageReader != null) return

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        width = metrics.widthPixels
        height = metrics.heightPixels
        density = metrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        virtualDisplay = projection.createVirtualDisplay(
            "AimsScreenCapture",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null,
            Handler(Looper.getMainLooper()),
        )
    }

    fun captureJpeg(context: Context, quality: Int = 70): ByteArray? {
        if (mediaProjection == null) return null

        ensureVirtualDisplay(context)

        val latch = CountDownLatch(1)
        var result: ByteArray? = null
        val handler = Handler(Looper.getMainLooper())

        handler.postDelayed({
            try {
                result = readLatestImage(quality)
            } finally {
                latch.countDown()
            }
        }, 120)

        latch.await(3, TimeUnit.SECONDS)
        return result
    }

    private fun readLatestImage(quality: Int): ByteArray? {
        val reader = imageReader ?: return null
        var image: Image? = null
        try {
            image = reader.acquireLatestImage() ?: return null
            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * width

            val bitmap = Bitmap.createBitmap(
                width + rowPadding / pixelStride,
                height,
                Bitmap.Config.ARGB_8888,
            )
            bitmap.copyPixelsFromBuffer(buffer)
            val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
            if (cropped != bitmap) bitmap.recycle()

            val scaled = scaleBitmap(cropped, 720)
            if (scaled != cropped) cropped.recycle()

            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
            scaled.recycle()
            return out.toByteArray()
        } finally {
            image?.close()
        }
    }

    private fun scaleBitmap(source: Bitmap, targetWidth: Int): Bitmap {
        if (source.width <= targetWidth) return source
        val ratio = targetWidth.toFloat() / source.width.toFloat()
        val h = (source.height * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(source, targetWidth, h, true)
    }
}
