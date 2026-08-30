package com.example.igen_app

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Android client — P2P save / open-file / open-folder helpers.
class MainActivity : FlutterActivity() {
    private val channelName = "com.example.igen_app/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getReceiveDirectory" -> {
                        try {
                            result.success(publicAimsPath())
                        } catch (e: Exception) {
                            result.error("dir_error", e.message, null)
                        }
                    }
                    "commitReceiveFile" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val displayName = call.argument<String>("displayName")
                        if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
                            result.error("bad_args", "sourcePath and displayName required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(commitReceiveFile(sourcePath, displayName))
                        } catch (e: Exception) {
                            result.error("commit_failed", e.message, null)
                        }
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        val contentUri = call.argument<String>("contentUri")
                        if (path.isNullOrBlank() && contentUri.isNullOrBlank()) {
                            result.error("bad_args", "path or contentUri required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(openFileWithChooser(path, contentUri))
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path")
                        try {
                            result.success(openFolderInManager(path))
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Display path for UI — files land here after commitReceiveFile. */
    private fun publicAimsPath(): String {
        val aims = aimsPublicDir()
        if (!aims.exists()) aims.mkdirs()
        return aims.absolutePath
    }

    private fun aimsPublicDir(): File {
        return File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Aims",
        )
    }

    /**
     * Copy a temp receive file into public Download/Aims (MediaStore on Android 10+).
     * Returns map with `path` and optional `contentUri`.
     */
    private fun commitReceiveFile(sourcePath: String, displayName: String): Map<String, String?> {
        val source = File(sourcePath)
        if (!source.exists()) throw IllegalStateException("source missing")

        val safeName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Aims")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert failed")

            resolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IllegalStateException("MediaStore stream failed")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            source.delete()

            val resolvedPath = File(aimsPublicDir(), safeName).absolutePath
            return mapOf("path" to resolvedPath, "contentUri" to uri.toString())
        }

        val destDir = aimsPublicDir()
        if (!destDir.exists()) destDir.mkdirs()
        val dest = File(destDir, safeName)
        source.copyTo(dest, overwrite = true)
        source.delete()
        return mapOf("path" to dest.absolutePath, "contentUri" to null)
    }

    private fun openFileWithChooser(path: String?, contentUri: String?): String {
        var uri: Uri? = null
        var mime = mimeFromName(path) ?: "*/*"

        if (!contentUri.isNullOrBlank()) {
            uri = Uri.parse(contentUri)
            mime = contentResolver.getType(uri!!) ?: mime
        }

        // Resolve MediaStore URI by file name when only a Display path is stored.
        if (uri == null && !path.isNullOrBlank()) {
            uri = findDownloadsUriByName(File(path).name)
            if (uri != null) {
                mime = contentResolver.getType(uri) ?: mime
            }
        }

        if (uri == null && !path.isNullOrBlank()) {
            val file = File(path)
            if (file.exists()) {
                uri = try {
                    FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file,
                    )
                } catch (_: Exception) {
                    // Scoped storage: copy into app cache then share via FileProvider.
                    try {
                        val cached = File(cacheDir, file.name)
                        file.copyTo(cached, overwrite = true)
                        FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            cached,
                        )
                    } catch (_: Exception) {
                        null
                    }
                }
                mime = mimeFor(file) ?: mime
            }
        }

        if (uri == null) return "missing"

        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        grantUriToResolvers(uri, view)

        val chooser = Intent.createChooser(view, "Open with").apply {
            clipData = android.content.ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(chooser)
            "ok"
        } catch (_: ActivityNotFoundException) {
            val any = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            grantUriToResolvers(uri, any)
            try {
                startActivity(
                    Intent.createChooser(any, "Open with").apply {
                        clipData = android.content.ClipData.newRawUri("", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
                "ok"
            } catch (_: ActivityNotFoundException) {
                "no_handler"
            }
        }
    }

    private fun findDownloadsUriByName(displayName: String): Uri? {
        if (displayName.isBlank()) return null
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.query(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Downloads._ID),
                    "${MediaStore.Downloads.DISPLAY_NAME}=?",
                    arrayOf(displayName),
                    "${MediaStore.Downloads.DATE_ADDED} DESC",
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val id = c.getLong(0)
                        return Uri.withAppendedPath(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id.toString())
                    }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun grantUriToResolvers(uri: Uri, intent: Intent) {
        val flags = PackageManager.MATCH_DEFAULT_ONLY
        val activities = packageManager.queryIntentActivities(intent, flags)
        for (info in activities) {
            try {
                grantUriPermission(
                    info.activityInfo.packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun openFolderInManager(path: String?): String {
        val aims = aimsPublicDir()
        if (!aims.exists()) aims.mkdirs()

        if (tryOpenDocumentsUi(aims)) return "ok"
        if (tryOpenGoogleFiles(aims)) return "ok"

        if (!path.isNullOrBlank()) {
            val target = File(path)
            val folder = if (target.isDirectory) target else target.parentFile
            if (folder != null) {
                if (tryOpenDocumentsUi(folder)) return "ok"
                if (tryOpenWithFolderMime(folder)) return "ok"
            }
        }

        if (tryOpenViewDownloads()) return "ok_downloads"

        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (tryOpenDocumentsUi(downloads)) return "ok_downloads"

        return "no_handler"
    }

    private fun tryOpenViewDownloads(): Boolean {
        val intents = listOf(
            Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS),
            Intent("android.intent.action.VIEW_DOWNLOADS"),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun tryOpenGoogleFiles(folder: File): Boolean {
        val rel = relativePrimaryPath(folder) ?: return false
        val docId = "primary:$rel"
        val uri = Uri.parse(
            "content://com.android.externalstorage.documents/document/${Uri.encode(docId)}",
        )
        val packages = listOf(
            "com.google.android.apps.nbu.files",
            "com.google.android.documentsui",
            "com.android.documentsui",
            "com.sec.android.app.myfiles",
            "com.mi.android.globalFileexplorer",
        )
        for (pkg in packages) {
            try {
                val launch = packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    launch.putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                    startActivity(launch)
                    return true
                }
            } catch (_: Exception) {
            }
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setPackage(pkg)
                    setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun tryOpenDocumentsUi(folder: File): Boolean {
        val rel = relativePrimaryPath(folder) ?: return false
        val docId = "primary:$rel"
        val uri = Uri.parse(
            "content://com.android.externalstorage.documents/document/${Uri.encode(docId)}",
        )

        val candidates = listOf(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
            },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "vnd.android.document/directory")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
            },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "resource/folder")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )

        for (intent in candidates) {
            try {
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }

        val components = listOf(
            "com.google.android.documentsui" to "com.android.documentsui.files.FilesActivity",
            "com.android.documentsui" to "com.android.documentsui.files.FilesActivity",
        )
        for ((pkg, cls) in components) {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setClassName(pkg, cls)
                    setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun tryOpenWithFolderMime(folder: File): Boolean {
        val folderPath = folder.absolutePath
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse("file://$folderPath"), "resource/folder")
            putExtra("org.openintents.extra.ABSOLUTE_PATH", folderPath)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(Intent.createChooser(intent, "Open folder"))
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    /** e.g. /storage/emulated/0/Download/Aims -> Download/Aims */
    private fun relativePrimaryPath(folder: File): String? {
        val abs = try {
            folder.canonicalPath
        } catch (_: Exception) {
            folder.absolutePath
        }
        val prefixes = mutableListOf(
            "/storage/emulated/0/",
            "/sdcard/",
        )
        Environment.getExternalStorageDirectory()?.absolutePath?.let {
            prefixes.add(0, if (it.endsWith("/")) it else "$it/")
        }
        for (prefix in prefixes) {
            if (abs.startsWith(prefix)) {
                return abs.removePrefix(prefix).trim('/')
            }
        }
        return null
    }

    private fun mimeFor(file: File): String? {
        val ext = file.name.substringAfterLast('.', "").lowercase()
        if (ext.isEmpty()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
    }

    private fun mimeFromName(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return mimeFor(File(path))
    }
}
