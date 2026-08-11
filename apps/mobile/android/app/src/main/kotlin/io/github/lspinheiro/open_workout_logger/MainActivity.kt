package io.github.lspinheiro.open_workout_logger

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null

    // a cold-start tap arrives before Flutter has registered its
    // callback. Buffer the payload until `timerNotificationsReady` drains it.
    private var flutterReady = false
    private var bufferedTapPayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TIMER_BACKGROUND_CHANNEL,
        )
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermissionIfNeeded" ->
                    requestNotificationPermission(result)
                "scheduleTimer" -> scheduleTimer(call, result)
                "cancelTimer" -> cancelTimer(call, result)
                "timerNotificationsReady" -> {
                    flutterReady = true
                    drainBufferedTap()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // A launch (cold start) from a timer notification carries its extras on
        // the Activity's intent.
        handleTimerNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A warm tap (app already running) delivers the extras here.
        setIntent(intent)
        handleTimerNotificationIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val result = pendingNotificationPermissionResult
            pendingNotificationPermissionResult = null
            val status = if (
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            ) {
                STATUS_GRANTED
            } else {
                STATUS_DENIED
            }
            result?.success(status)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun handleTimerNotificationIntent(intent: Intent?) {
        if (intent?.action != TimerForegroundService.ACTION_OPEN_TIMER) {
            return
        }
        val payload = mapOf(
            "timerId" to intent.getStringExtra(TimerForegroundService.EXTRA_TIMER_ID),
            "workoutId" to
                intent.getStringExtra(TimerForegroundService.EXTRA_WORKOUT_ID),
            "workoutExerciseId" to intent.getStringExtra(
                TimerForegroundService.EXTRA_WORKOUT_EXERCISE_ID,
            ),
        )
        // Consume the extras so a config change / re-launch doesn't re-fire.
        intent.action = null

        if (flutterReady) {
            methodChannel?.invokeMethod("onTimerNotificationTapped", payload)
        } else {
            bufferedTapPayload = payload
        }
    }

    private fun drainBufferedTap() {
        val payload = bufferedTapPayload ?: return
        bufferedTapPayload = null
        methodChannel?.invokeMethod("onTimerNotificationTapped", payload)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(STATUS_GRANTED)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(STATUS_GRANTED)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.success(STATUS_DENIED)
            return
        }

        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun scheduleTimer(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(STATUS_DENIED)
            return
        }

        val intent = TimerForegroundService.intentFrom(
            context = this,
            arguments = call.arguments as? Map<*, *>,
        ) ?: run {
            result.error(
                "invalid_timer_schedule",
                "Timer schedule payload is missing required fields.",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(STATUS_GRANTED)
    }

    private fun cancelTimer(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val timerId = arguments?.get("timerId") as? String
        if (timerId == null) {
            result.error(
                "invalid_timer_cancel",
                "Timer cancel payload is missing timerId.",
                null,
            )
            return
        }

        startService(TimerForegroundService.cancelIntent(this, timerId))
        result.success(null)
    }

    companion object {
        private const val TIMER_BACKGROUND_CHANNEL =
            "open_workout_logger/timer_background"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4207
        private const val STATUS_GRANTED = "granted"
        private const val STATUS_DENIED = "denied"
    }
}
