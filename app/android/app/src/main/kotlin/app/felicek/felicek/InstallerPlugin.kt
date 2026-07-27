package app.felicek.felicek

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The Android half of the self-hosted APK updater.
 *
 * Felicek is distributed from a website rather than the Play Store, so it
 * needs to hand a downloaded, checksum-verified APK to the system package
 * installer. Android then shows *its own* confirmation dialog before
 * replacing the app — outside a device-owner (enterprise) deployment, no app
 * can silently overwrite itself, and this class does not pretend otherwise.
 * "Auto-update" here means: detected, downloaded, verified and queued for
 * install automatically, with one system tap to confirm.
 *
 * The Dart side is `UpdateService`; the channel name must match
 * `UpdateService.installerChannelName`.
 */
object InstallerPlugin {

    private const val CHANNEL = "app.felicek/installer"

    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(activity, call, result) }
    }

    private fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> result.success(installApk(activity, call.argument<String>("path")))
            "canRequestInstalls" -> result.success(canRequestInstalls(activity))
            "openInstallPermissionSettings" -> {
                openInstallPermissionSettings(activity)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Launches the package installer for [path].
     *
     * Returns false — rather than throwing — when the user has not granted
     * "install unknown apps" for this app, so the Dart side can show a
     * readable explanation and a shortcut into Settings instead of a crash.
     */
    private fun installApk(activity: Activity, path: String?): Boolean {
        if (path.isNullOrBlank()) return false
        val file = File(path)
        if (!file.exists() || file.length() == 0L) return false
        if (!canRequestInstalls(activity)) return false

        return try {
            // A raw file:// URI throws FileUriExposedException on API 24+.
            val uri: Uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun canRequestInstalls(activity: Activity): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallPermissionSettings(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (e: Exception) {
            // Some OEM builds hide the per-app screen; fall back to the list.
            try {
                activity.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (ignored: Exception) {
                // Nothing further we can do; the Dart side already explains it.
            }
        }
    }
}
