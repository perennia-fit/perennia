package fit.perennia.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Handles `perennia/backup_export`. Settings → Back up now hands a finished
 * backup here, and the system "save as" screen (`ACTION_CREATE_DOCUMENT`)
 * lets the user put it anywhere a document provider offers (Downloads, a
 * cloud drive) without a storage permission. Why this is a foreground save
 * and not a scheduled folder backup is recorded on `BackupExportService` in
 * Dart.
 *
 * Answers `saved`, `cancelled` or `unsupported` (no app handles the intent),
 * or fails with `backup_write_failed` when the chosen document cannot be
 * written.
 */
class BackupExportChannel(private val activity: Activity) {
    private class PendingSave(val bytes: ByteArray, val result: MethodChannel.Result)

    private var pending: PendingSave? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveFile" -> saveFile(call, result)
            else -> result.notImplemented()
        }
    }

    /** True when [requestCode] was this channel's save screen. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_REQUEST_CODE) {
            return false
        }
        val save = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            save.result.success(STATUS_CANCELLED)
            return true
        }
        // A backup can run to megabytes; keep the write off the UI thread.
        ioExecutor.execute { write(uri, save) }
        return true
    }

    private fun saveFile(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType") ?: "application/zip"
        if (fileName == null || bytes == null) {
            result.error(
                "invalid_backup_export",
                "Backup export payload is missing fileName or bytes.",
                null,
            )
            return
        }
        if (pending != null) {
            result.error(
                "backup_export_busy",
                "A backup save screen is already open.",
                null,
            )
            return
        }

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        pending = PendingSave(bytes, result)
        try {
            activity.startActivityForResult(intent, SAVE_REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            pending = null
            result.success(STATUS_UNSUPPORTED)
        }
    }

    private fun write(uri: Uri, save: PendingSave) {
        try {
            val stream = activity.contentResolver.openOutputStream(uri, "w")
                ?: throw IOException("No output stream for $uri")
            stream.use { it.write(save.bytes) }
            mainHandler.post { save.result.success(STATUS_SAVED) }
        } catch (error: Exception) {
            // The save screen already created the document; don't leave an
            // empty or partial backup behind that a later restore would trip
            // over.
            try {
                DocumentsContract.deleteDocument(activity.contentResolver, uri)
            } catch (ignored: Exception) {
            }
            mainHandler.post {
                save.result.error("backup_write_failed", error.message, null)
            }
        }
    }

    companion object {
        const val CHANNEL = "perennia/backup_export"
        private const val SAVE_REQUEST_CODE = 4208
        private const val STATUS_SAVED = "saved"
        private const val STATUS_CANCELLED = "cancelled"
        private const val STATUS_UNSUPPORTED = "unsupported"
    }
}
