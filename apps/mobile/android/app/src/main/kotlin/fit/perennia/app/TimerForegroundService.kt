package fit.perennia.app

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
    private var getReadyText: String? = null
    private var prepareText = ""
    private var workoutId: String? = null
    private var workoutExerciseId: String? = null
    private var soundEnabled = true
    private var getReadyPassed = false
    private var preparePassed = false
    private var endPassed = false

    private val tick = object : Runnable {
        override fun run() {
            val remainingMillis = deadlineAtMillis - System.currentTimeMillis()
            if (remainingMillis <= 0L) {
                finishAtDeadline()
                return
            }

            if (!getReadyPassed && remainingMillis <= GET_READY_WINDOW_MILLIS) {
                getReadyPassed = true
                if (!appPlaysCues()) {
                    notificationManager.notify(
                        getReadyNotificationId(timerId),
                        buildGetReadyNotification(),
                    )
                }
            }

            if (!preparePassed && remainingMillis <= PREPARE_WINDOW_MILLIS) {
                preparePassed = true
                if (!appPlaysCues()) {
                    notificationManager.notify(
                        prepareNotificationId(timerId),
                        buildPrepareNotification(),
                    )
                }
            }

            notificationManager.notify(
                notificationId(timerId),
                buildNotification(remainingMillis, complete = false),
            )
            handler.postDelayed(this, ONE_SECOND_MILLIS)
        }
    }

    /**
     * The service stops at the deadline either way. When no end notification
     * replaces the ongoing countdown, the countdown has to be removed: detached,
     * it would stay in the shade as a stuck "Rest 0:01".
     */
    private fun finishAtDeadline() {
        val postEnd = !endPassed && !appPlaysCues()
        endPassed = true
        if (postEnd) {
            notificationManager.notify(
                notificationId(timerId),
                buildNotification(0L, complete = true),
            )
            detachForegroundNotification()
        } else {
            removeForegroundNotification()
        }
        stopSelf()
    }

    // Each threshold has exactly one cue: the app's while it is visible and a
    // strip on the current route is showing the rest, this service's otherwise.
    private fun appPlaysCues(): Boolean {
        return MainActivity.isStarted && inAppCuesActive
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
            // Clears what is posted outside the foreground slot: the end
            // notification and the two one-shot cues. The system ignores an
            // app's cancel of a live foreground notification, so the running
            // countdown is removed by stopForeground below. Detached instead,
            // it would stay in the shade as a stuck "Rest 0:01".
            notificationManager.cancel(notificationId(id))
            notificationManager.cancel(prepareNotificationId(id))
            notificationManager.cancel(getReadyNotificationId(id))
            if (id == timerId || timerId.isEmpty()) {
                handler.removeCallbacks(tick)
                removeForegroundNotification()
                stopSelf()
            }
            return START_NOT_STICKY
        }

        timerId = intent.getStringExtra(EXTRA_TIMER_ID).orEmpty()
        deadlineAtMillis = intent.getLongExtra(EXTRA_DEADLINE_AT_MILLIS, 0L)
        title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        countdownLabel = intent.getStringExtra(EXTRA_COUNTDOWN_LABEL).orEmpty()
        getReadyText = intent.getStringExtra(EXTRA_GET_READY_TEXT)
        prepareText = intent.getStringExtra(EXTRA_PREPARE_TEXT).orEmpty()
        workoutId = intent.getStringExtra(EXTRA_WORKOUT_ID)
        workoutExerciseId = intent.getStringExtra(EXTRA_WORKOUT_EXERCISE_ID)
        soundEnabled = intent.getBooleanExtra(EXTRA_SOUND_ENABLED, true)

        handler.removeCallbacks(tick)
        val remainingMillis = deadlineAtMillis - System.currentTimeMillis()
        // A threshold at or behind the remaining time when a schedule starts is
        // already passed, so the first tick never posts a stale cue.
        getReadyPassed =
            getReadyText == null || remainingMillis <= GET_READY_WINDOW_MILLIS
        preparePassed = remainingMillis <= PREPARE_WINDOW_MILLIS
        endPassed = remainingMillis <= 0L
        // Always the countdown form, even at 0: the end form would sound the end
        // cue of a schedule that starts at or past its deadline.
        startForeground(
            notificationId(timerId),
            buildNotification(max(0L, remainingMillis), complete = false),
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

        // A channel's sound can't change after the channel is created, so a new
        // sound needs a new channel id. The sound is addressed by name
        // (rawSoundUri), since aapt2 assigns R.raw ids in name order and a new
        // file would shift an id-addressed one to the wrong tone.
        createAlertChannels(
            GET_READY_CHANNEL_ID,
            GET_READY_SILENT_CHANNEL_ID,
            R.string.timer_get_ready_channel_name,
            R.string.timer_get_ready_silent_channel_name,
            R.string.timer_get_ready_channel_description,
            "get_ready",
        )
        createAlertChannels(
            PREPARE_CHANNEL_ID,
            PREPARE_SILENT_CHANNEL_ID,
            R.string.timer_prepare_channel_name,
            R.string.timer_prepare_silent_channel_name,
            R.string.timer_prepare_channel_description,
            "prepare_beep",
        )
        createAlertChannels(
            COMPLETION_CHANNEL_ID,
            COMPLETION_SILENT_CHANNEL_ID,
            R.string.timer_completion_channel_name,
            R.string.timer_completion_silent_channel_name,
            R.string.timer_completion_channel_description,
            "timer_complete",
        )

        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_V2_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_PREPARE_CHANNEL_ID)
    }

    /**
     * A sounded channel and its silent twin. On Android 8 and later a
     * notification's sound and vibration come from its channel, so Rest timer
     * sounds off has to post to the twin.
     */
    private fun createAlertChannels(
        soundedId: String,
        silentId: String,
        nameRes: Int,
        silentNameRes: Int,
        descriptionRes: Int,
        soundName: String,
    ) {
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .build()
        val sounded = NotificationChannel(
            soundedId,
            getString(nameRes),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(descriptionRes)
            setSound(rawSoundUri(soundName), audioAttributes)
            enableVibration(true)
        }
        notificationManager.createNotificationChannel(sounded)

        val silent = NotificationChannel(
            silentId,
            getString(silentNameRes),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(descriptionRes)
            setSound(null, null)
            enableVibration(false)
        }
        notificationManager.createNotificationChannel(silent)
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
                when {
                    !complete -> COUNTDOWN_CHANNEL_ID
                    soundEnabled -> COMPLETION_CHANNEL_ID
                    else -> COMPLETION_SILENT_CHANNEL_ID
                },
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
                    // Below API 26 there are no channels, so the sound and
                    // vibration are muted on the notification itself.
                    setSound(null)
                    setDefaults(0)
                    setVibrate(null)
                }
            }
            .build()
    }

    private fun buildGetReadyNotification(): Notification {
        return buildCueNotification(
            channelId = if (soundEnabled) {
                GET_READY_CHANNEL_ID
            } else {
                GET_READY_SILENT_CHANNEL_ID
            },
            text = getReadyText.orEmpty(),
            timeoutMillis = GET_READY_WINDOW_MILLIS,
        )
    }

    private fun buildPrepareNotification(): Notification {
        return buildCueNotification(
            channelId = if (soundEnabled) {
                PREPARE_CHANNEL_ID
            } else {
                PREPARE_SILENT_CHANNEL_ID
            },
            text = prepareText,
            timeoutMillis = PREPARE_WINDOW_MILLIS + ONE_SECOND_MILLIS,
        )
    }

    private fun buildCueNotification(
        channelId: String,
        text: String,
        timeoutMillis: Long,
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setTimeoutAfter(timeoutMillis)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent())
            .setOngoing(false)
            .setAutoCancel(true)
            .setShowWhen(false)
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

    // By name, so no later file can shift it. The shrinker can't see this URI;
    // TimerCueSounds' direct R.raw references are what keep the files in a
    // release APK.
    private fun rawSoundUri(name: String): Uri {
        return Uri.parse("android.resource://$packageName/raw/$name")
    }

    private fun detachForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
    }

    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun formatRemaining(remainingMillis: Long): String {
        val totalSeconds = max(0L, (remainingMillis + 999L) / ONE_SECOND_MILLIS)
        val minutes = totalSeconds / 60L
        val seconds = totalSeconds % 60L
        return "%d:%02d".format(minutes, seconds)
    }

    companion object {
        /**
         * Whether a rest strip on the current route is showing a running rest,
         * and so plays its cues in the app. Set by [MainActivity], and read on
         * every tick.
         */
        @Volatile
        var inAppCuesActive = false

        private const val COUNTDOWN_CHANNEL_ID = "workout_timer_countdowns"
        private const val GET_READY_CHANNEL_ID = "workout_timer_get_ready_v1"
        private const val GET_READY_SILENT_CHANNEL_ID =
            "workout_timer_get_ready_v1_silent"
        private const val PREPARE_CHANNEL_ID = "workout_timer_prepare_v3"
        private const val PREPARE_SILENT_CHANNEL_ID =
            "workout_timer_prepare_v3_silent"
        private const val COMPLETION_CHANNEL_ID = "workout_timer_completions_v3"
        private const val COMPLETION_SILENT_CHANNEL_ID =
            "workout_timer_completions_v3_silent"
        private const val LEGACY_COMPLETION_CHANNEL_ID = "workout_timer_completions"
        private const val LEGACY_COMPLETION_V2_CHANNEL_ID =
            "workout_timer_completions_v2"
        private const val LEGACY_PREPARE_CHANNEL_ID = "workout_timer_prepare"
        private const val ONE_SECOND_MILLIS = 1000L
        private const val GET_READY_WINDOW_MILLIS = 10000L
        private const val PREPARE_WINDOW_MILLIS = 3000L
        private const val ACTION_CANCEL =
            "fit.perennia.app.CANCEL_TIMER"
        const val ACTION_OPEN_TIMER =
            "fit.perennia.app.OPEN_TIMER"
        const val EXTRA_TIMER_ID = "timerId"
        private const val EXTRA_DEADLINE_AT_MILLIS = "deadlineAtMillis"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_COUNTDOWN_LABEL = "countdownLabel"
        private const val EXTRA_GET_READY_TEXT = "getReadyText"
        private const val EXTRA_PREPARE_TEXT = "prepareText"
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
            val prepareText = arguments[EXTRA_PREPARE_TEXT] as? String ?: return null
            val soundEnabled = arguments[EXTRA_SOUND_ENABLED] as? Boolean ?: true

            return Intent(context, TimerForegroundService::class.java).apply {
                putExtra(EXTRA_TIMER_ID, timerId)
                putExtra(EXTRA_DEADLINE_AT_MILLIS, deadlineAtMillis)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_COUNTDOWN_LABEL, countdownLabel)
                putExtra(EXTRA_GET_READY_TEXT, arguments[EXTRA_GET_READY_TEXT] as? String)
                putExtra(EXTRA_PREPARE_TEXT, prepareText)
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

        private fun getReadyNotificationId(timerId: String): Int {
            return notificationId("getReady:$timerId")
        }
    }
}
