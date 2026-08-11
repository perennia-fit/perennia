package io.github.lspinheiro.open_workout_logger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.math.max

class TimerForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var notificationManager: NotificationManager
    private var timerId = ""
    private var deadlineAtMillis = 0L
    private var title = ""
    private var body = ""
    private var countdownLabel = ""
    private var workoutId: String? = null
    private var workoutExerciseId: String? = null
    private var soundEnabled = true
    private var prepareNotified = false

    private val tick = object : Runnable {
        override fun run() {
            val remainingMillis = deadlineAtMillis - System.currentTimeMillis()
            if (remainingMillis <= 0L) {
                notificationManager.notify(
                    notificationId(timerId),
                    buildNotification(0L, complete = true),
                )
                detachForegroundNotification()
                stopSelf()
                return
            }

            // fire the 3-2-1 prepare cue once, when the countdown first
            // crosses into the last 3 seconds.
            if (!prepareNotified && remainingMillis <= PREPARE_WINDOW_MILLIS) {
                prepareNotified = true
                notificationManager.notify(
                    prepareNotificationId(timerId),
                    buildPrepareNotification(),
                )
            }

            notificationManager.notify(
                notificationId(timerId),
                buildNotification(remainingMillis, complete = false),
            )
            handler.postDelayed(this, ONE_SECOND_MILLIS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            return START_NOT_STICKY
        }
        if (intent.action == ACTION_CANCEL) {
            val id = intent.getStringExtra(EXTRA_TIMER_ID).orEmpty()
            notificationManager.cancel(notificationId(id))
            notificationManager.cancel(prepareNotificationId(id))
            if (id == timerId || timerId.isEmpty()) {
                handler.removeCallbacks(tick)
                detachForegroundNotification()
                stopSelf()
            }
            return START_NOT_STICKY
        }

        timerId = intent.getStringExtra(EXTRA_TIMER_ID).orEmpty()
        deadlineAtMillis = intent.getLongExtra(EXTRA_DEADLINE_AT_MILLIS, 0L)
        title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        countdownLabel = intent.getStringExtra(EXTRA_COUNTDOWN_LABEL).orEmpty()
        workoutId = intent.getStringExtra(EXTRA_WORKOUT_ID)
        workoutExerciseId = intent.getStringExtra(EXTRA_WORKOUT_EXERCISE_ID)
        soundEnabled = intent.getBooleanExtra(EXTRA_SOUND_ENABLED, true)
        prepareNotified = false

        handler.removeCallbacks(tick)
        val remainingMillis = max(0L, deadlineAtMillis - System.currentTimeMillis())
        startForeground(
            notificationId(timerId),
            buildNotification(remainingMillis, complete = remainingMillis == 0L),
        )
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            COUNTDOWN_CHANNEL_ID,
            getString(R.string.timer_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.timer_notification_channel_description)
        }
        notificationManager.createNotificationChannel(channel)

        // a channel's sound is IMMUTABLE after first creation, so the
        // custom-sound completion channel gets a fresh `_v2` id and the old
        // silent-defaults one is removed (approved pre-1.0 cleanup).
        val completionAudioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .build()
        val completionChannel = NotificationChannel(
            COMPLETION_CHANNEL_ID,
            getString(R.string.timer_completion_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.timer_completion_channel_description)
            setSound(rawSoundUri(R.raw.timer_complete), completionAudioAttributes)
            enableVibration(true)
        }
        notificationManager.createNotificationChannel(completionChannel)

        val prepareChannel = NotificationChannel(
            PREPARE_CHANNEL_ID,
            getString(R.string.timer_prepare_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.timer_prepare_channel_description)
            setSound(rawSoundUri(R.raw.prepare_beep), completionAudioAttributes)
            enableVibration(true)
        }
        notificationManager.createNotificationChannel(prepareChannel)

        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_CHANNEL_ID)
    }

    private fun buildNotification(
        remainingMillis: Long,
        complete: Boolean,
    ): Notification {
        val contentText = if (complete) {
            body
        } else {
            "$countdownLabel ${formatRemaining(remainingMillis)}"
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(
                this,
                if (complete) COMPLETION_CHANNEL_ID else COUNTDOWN_CHANNEL_ID,
            )
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(contentText)
            .setContentIntent(contentIntent())
            .setOngoing(!complete)
            .setOnlyAlertOnce(!complete)
            .setAutoCancel(complete)
            .setShowWhen(false)
            .setPriority(
                if (complete) {
                    Notification.PRIORITY_HIGH
                } else {
                    Notification.PRIORITY_LOW
                },
            )
            .apply {
                if (complete && !soundEnabled) {
                    // Toggle off: keep the visual alert, but no sound/vibration
                    // (the channel's sound still applies on first post, so mute
                    // it explicitly on the notification too).
                    setSound(null)
                    setDefaults(0)
                    setVibrate(null)
                }
            }
            .build()
    }

    private fun buildPrepareNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, PREPARE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText("$countdownLabel ${formatRemaining(PREPARE_WINDOW_MILLIS)}")
            .setContentIntent(contentIntent())
            .setOngoing(false)
            .setAutoCancel(true)
            .setShowWhen(false)
            .setTimeoutAfter(PREPARE_WINDOW_MILLIS + ONE_SECOND_MILLIS)
            .setPriority(Notification.PRIORITY_HIGH)
            .apply {
                if (!soundEnabled) {
                    setSound(null)
                    setDefaults(0)
                    setVibrate(null)
                }
            }
            .build()
    }

    /**
     * PendingIntent that reopens the app on the exercise that owns this timer.
     * The ids are read back in [MainActivity] via `onNewIntent` /
     * the launch intent.
     */
    private fun contentIntent(): PendingIntent {
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_TIMER
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_TIMER_ID, timerId)
            putExtra(EXTRA_WORKOUT_ID, workoutId)
            putExtra(EXTRA_WORKOUT_EXERCISE_ID, workoutExerciseId)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(
            this,
            notificationId(timerId),
            launch,
            flags,
        )
    }

    private fun rawSoundUri(resId: Int): Uri {
        return Uri.parse("android.resource://$packageName/$resId")
    }

    private fun detachForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
    }

    private fun formatRemaining(remainingMillis: Long): String {
        val totalSeconds = max(0L, (remainingMillis + 999L) / ONE_SECOND_MILLIS)
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L
        return "%d:%02d".format(minutes, seconds)
    }

    companion object {
        private const val COUNTDOWN_CHANNEL_ID = "workout_timer_countdowns"
        private const val COMPLETION_CHANNEL_ID = "workout_timer_completions_v2"
        private const val LEGACY_COMPLETION_CHANNEL_ID = "workout_timer_completions"
        private const val PREPARE_CHANNEL_ID = "workout_timer_prepare"
        private const val ONE_SECOND_MILLIS = 1000L
        private const val PREPARE_WINDOW_MILLIS = 3000L
        private const val ACTION_CANCEL =
            "io.github.lspinheiro.open_workout_logger.CANCEL_TIMER"
        const val ACTION_OPEN_TIMER =
            "io.github.lspinheiro.open_workout_logger.OPEN_TIMER"
        const val EXTRA_TIMER_ID = "timerId"
        private const val EXTRA_DEADLINE_AT_MILLIS = "deadlineAtMillis"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_COUNTDOWN_LABEL = "countdownLabel"
        const val EXTRA_WORKOUT_ID = "workoutId"
        const val EXTRA_WORKOUT_EXERCISE_ID = "workoutExerciseId"
        private const val EXTRA_SOUND_ENABLED = "soundEnabled"

        fun intentFrom(context: Context, arguments: Map<*, *>?): Intent? {
            val timerId = arguments?.get(EXTRA_TIMER_ID) as? String ?: return null
            val deadlineAtMillis =
                (arguments[EXTRA_DEADLINE_AT_MILLIS] as? Number)?.toLong()
                    ?: return null
            val title = arguments[EXTRA_TITLE] as? String ?: return null
            val body = arguments[EXTRA_BODY] as? String ?: return null
            val countdownLabel =
                arguments[EXTRA_COUNTDOWN_LABEL] as? String ?: return null
            val soundEnabled = arguments[EXTRA_SOUND_ENABLED] as? Boolean ?: true

            return Intent(context, TimerForegroundService::class.java).apply {
                putExtra(EXTRA_TIMER_ID, timerId)
                putExtra(EXTRA_DEADLINE_AT_MILLIS, deadlineAtMillis)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_COUNTDOWN_LABEL, countdownLabel)
                putExtra(EXTRA_WORKOUT_ID, arguments[EXTRA_WORKOUT_ID] as? String)
                putExtra(
                    EXTRA_WORKOUT_EXERCISE_ID,
                    arguments[EXTRA_WORKOUT_EXERCISE_ID] as? String,
                )
                putExtra(EXTRA_SOUND_ENABLED, soundEnabled)
            }
        }

        fun cancelIntent(context: Context, timerId: String): Intent {
            return Intent(context, TimerForegroundService::class.java).apply {
                action = ACTION_CANCEL
                putExtra(EXTRA_TIMER_ID, timerId)
            }
        }

        private fun notificationId(timerId: String): Int {
            return timerId.hashCode().takeIf { it != Int.MIN_VALUE }?.let {
                kotlin.math.abs(it)
            } ?: 1
        }

        private fun prepareNotificationId(timerId: String): Int {
            // Distinct id so the one-shot prepare cue never replaces the live
            // countdown notification.
            return notificationId("prepare:$timerId")
        }
    }
}
