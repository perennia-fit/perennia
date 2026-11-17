package fit.perennia.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
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
    private var alertVolume = 1f
    private var getReadyPassed = false
    private var preparePassed = false
    private var tickTwoPassed = false
    private var tickOnePassed = false
    private var endPassed = false

    // stopSelf(id) only stops when id is the newest start, so stopAfterEnd can't
    // destroy the service ahead of a start that is still queued.
    private var lastStartId = 0

    /**
     * The service plays the tones itself because Android mutes the later
     * alerting notifications of a rest, which would leave the end silent on a
     * locked phone. See "Why Android's service plays the background cues" in
     * docs/designs/workout-feedback.md.
     */
    private var cues: TimerCueSounds? = null

    /**
     * A [Handler] stops when the CPU suspends, so with the screen off the ticks,
     * and so the cues, would run late without this.
     */
    private var wakeLock: PowerManager.WakeLock? = null

    private val tick = object : Runnable {
        override fun run() {
            val remainingMillis = deadlineAtMillis - System.currentTimeMillis()
            // One reading per tick, so its cue, its notifications and the end
            // can't disagree about who plays.
            val appPlays = appPlaysCues()
            // Before the deadline check: a late tick that crosses the deadline
            // still posts the notifications of the thresholds it passed.
            val cue = passThresholds(remainingMillis, appPlays)

            if (remainingMillis <= 0L) {
                finishAtDeadline(appPlays)
                return
            }

            if (cue != null && !appPlays && soundEnabled) {
                cues?.play(cue, alertVolume)
            }

            notificationManager.notify(
                notificationId(timerId),
                buildNotification(remainingMillis, complete = false),
            )
            // Lands the ticks on the deadline's whole seconds, which is where the
            // thresholds are.
            val toNextSecond = remainingMillis % ONE_SECOND_MILLIS
            handler.postDelayed(
                this,
                if (toNextSecond == 0L) ONE_SECOND_MILLIS else toNextSecond,
            )
        }
    }

    /**
     * Keeps the service alive after the end cue, so onDestroy doesn't release the
     * players and cut the tone. stopSelf(lastStartId), not stopSelf(), so that a
     * start queued behind the deadline survives.
     */
    private val stopAfterEnd = Runnable { stopSelf(lastStartId) }

    /**
     * Marks passed every threshold [remainingMillis] has reached and, unless the
     * app plays, posts the get-ready and prepare notifications among them. Returns
     * the cue of the one nearest the deadline, the only one a late tick plays, or
     * null when none was just passed.
     */
    private fun passThresholds(remainingMillis: Long, appPlays: Boolean): String? {
        var cue: String? = null
        if (!getReadyPassed && remainingMillis <= GET_READY_WINDOW_MILLIS) {
            getReadyPassed = true
            cue = "getReady"
            if (!appPlays) {
                notificationManager.notify(
                    getReadyNotificationId(timerId),
                    buildGetReadyNotification(),
                )
            }
        }
        if (!preparePassed && remainingMillis <= PREPARE_WINDOW_MILLIS) {
            preparePassed = true
            cue = "countdown"
            if (!appPlays) {
                notificationManager.notify(
                    prepareNotificationId(timerId),
                    buildPrepareNotification(),
                )
            }
        }
        if (!tickTwoPassed && remainingMillis <= TICK_TWO_MILLIS) {
            tickTwoPassed = true
            cue = "tick"
        }
        if (!tickOnePassed && remainingMillis <= TICK_ONE_MILLIS) {
            tickOnePassed = true
            cue = "tick"
        }
        return cue
    }

    /**
     * The service stops at the deadline either way. When no end notification
     * replaces the ongoing countdown, the countdown has to be removed: detached,
     * it would stay in the shade as a stuck "Rest 0:01".
     *
     * Only `end` plays here, even when this tick crossed other thresholds. It
     * plays before the notify and the detach: Android ignores vibrations from a
     * background process, so the vibration has to start while this is still a
     * foreground service. With a tone sounding, the stop then waits
     * [END_TONE_HOLD_MILLIS]; with none, it runs at once.
     */
    private fun finishAtDeadline(appPlays: Boolean) {
        val postEnd = !endPassed && !appPlays
        endPassed = true
        val playEnd = postEnd && soundEnabled
        if (playEnd) {
            cues?.play("end", alertVolume)
        }
        if (postEnd) {
            notificationManager.notify(
                notificationId(timerId),
                buildNotification(0L, complete = true),
            )
            detachForegroundNotification()
        } else {
            removeForegroundNotification()
        }
        if (playEnd) {
            handler.postDelayed(stopAfterEnd, END_TONE_HOLD_MILLIS)
        } else {
            stopAfterEnd.run()
        }
    }

    // Each threshold has exactly one cue: the app's while it is visible and a
    // strip on the current route is showing the rest, this service's otherwise.
    // Read once per tick.
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
        lastStartId = startId
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
            // A cancel for another timer leaves stopAfterEnd running. It doesn't
            // stop the service, so removing the hold would leave nothing that does.
            if (id == timerId || timerId.isEmpty()) {
                handler.removeCallbacks(tick)
                handler.removeCallbacks(stopAfterEnd)
                removeForegroundNotification()
                // Only if no start is queued behind this cancel, as with -15 s
                // or a Log set during a rest. Stopping would destroy the service
                // before that start's startForeground, which crashes the app.
                stopSelf(startId)
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
        alertVolume = intent.getFloatExtra(EXTRA_ALERT_VOLUME, 1f)

        handler.removeCallbacks(tick)
        handler.removeCallbacks(stopAfterEnd)
        val remainingMillis = deadlineAtMillis - System.currentTimeMillis()
        // A threshold at or behind the remaining time when a schedule starts is
        // already passed, so the first tick never posts a stale cue.
        getReadyPassed =
            getReadyText == null || remainingMillis <= GET_READY_WINDOW_MILLIS
        preparePassed = remainingMillis <= PREPARE_WINDOW_MILLIS
        tickTwoPassed = remainingMillis <= TICK_TWO_MILLIS
        tickOnePassed = remainingMillis <= TICK_ONE_MILLIS
        endPassed = remainingMillis <= 0L
        // Always the countdown form, even at 0: the end form would sound the end
        // cue of a schedule that starts at or past its deadline.
        startForeground(
            notificationId(timerId),
            buildNotification(max(0L, remainingMillis), complete = false),
        )
        // Everything that can fail comes after startForeground, which the system
        // requires within 5 s. On this path only: a cancel can itself start a
        // fresh service, which must not load players or hold the CPU.
        if (cues == null) {
            cues = TimerCueSounds(this).also { it.prepare() }
        }
        holdWakeLock(remainingMillis)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        handler.removeCallbacks(stopAfterEnd)
        cues?.release()
        cues = null
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        super.onDestroy()
    }

    /**
     * Not reference counted, so each schedule's acquire replaces the last one's
     * timeout. The 5 s past the deadline covers the end tone's hold.
     */
    private fun holdWakeLock(remainingMillis: Long) {
        val lock = wakeLock
            ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                .apply { setReferenceCounted(false) }
                .also { wakeLock = it }
        lock.acquire(max(0L, remainingMillis) + WAKE_LOCK_MARGIN_MILLIS)
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

        createAlertChannel(
            GET_READY_SILENT_CHANNEL_ID,
            R.string.timer_get_ready_channel_name,
            R.string.timer_get_ready_channel_description,
        )
        createAlertChannel(
            PREPARE_SILENT_CHANNEL_ID,
            R.string.timer_prepare_channel_name,
            R.string.timer_prepare_channel_description,
        )
        createAlertChannel(
            COMPLETION_SILENT_CHANNEL_ID,
            R.string.timer_completion_channel_name,
            R.string.timer_completion_channel_description,
        )

        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_V2_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_PREPARE_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_GET_READY_V1_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_PREPARE_V3_CHANNEL_ID)
        notificationManager.deleteNotificationChannel(LEGACY_COMPLETION_V3_CHANNEL_ID)
    }

    /**
     * High importance keeps the heads-up, with no sound or vibration, because the
     * service plays the cues itself. The ids keep their "_silent" suffix: those
     * channels already exist silent, and a channel's sound can't change after
     * the channel is created.
     */
    private fun createAlertChannel(id: String, nameRes: Int, descriptionRes: Int) {
        val channel = NotificationChannel(
            id,
            getString(nameRes),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(descriptionRes)
            setSound(null, null)
            enableVibration(false)
        }
        notificationManager.createNotificationChannel(channel)
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
                if (complete) COMPLETION_SILENT_CHANNEL_ID else COUNTDOWN_CHANNEL_ID,
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
                if (complete) {
                    // The service plays the cues, so a notification never sounds.
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
            channelId = GET_READY_SILENT_CHANNEL_ID,
            text = getReadyText.orEmpty(),
            timeoutMillis = GET_READY_WINDOW_MILLIS,
        )
    }

    private fun buildPrepareNotification(): Notification {
        return buildCueNotification(
            channelId = PREPARE_SILENT_CHANNEL_ID,
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
            // The service plays the cues, so a notification never sounds. Below
            // API 26 there are no channels, so the sound and vibration are muted
            // on the notification itself.
            .setSound(null)
            .setDefaults(0)
            .setVibrate(null)
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
        private const val GET_READY_SILENT_CHANNEL_ID =
            "workout_timer_get_ready_v1_silent"
        private const val PREPARE_SILENT_CHANNEL_ID =
            "workout_timer_prepare_v3_silent"
        private const val COMPLETION_SILENT_CHANNEL_ID =
            "workout_timer_completions_v3_silent"
        private const val LEGACY_COMPLETION_CHANNEL_ID = "workout_timer_completions"
        private const val LEGACY_COMPLETION_V2_CHANNEL_ID =
            "workout_timer_completions_v2"
        private const val LEGACY_PREPARE_CHANNEL_ID = "workout_timer_prepare"
        private const val LEGACY_GET_READY_V1_CHANNEL_ID = "workout_timer_get_ready_v1"
        private const val LEGACY_PREPARE_V3_CHANNEL_ID = "workout_timer_prepare_v3"
        private const val LEGACY_COMPLETION_V3_CHANNEL_ID =
            "workout_timer_completions_v3"
        private const val ONE_SECOND_MILLIS = 1000L
        private const val GET_READY_WINDOW_MILLIS = 10000L
        private const val PREPARE_WINDOW_MILLIS = 3000L
        private const val TICK_TWO_MILLIS = 2000L
        private const val TICK_ONE_MILLIS = 1000L

        /** Long enough for `timer_complete` to finish before onDestroy. */
        private const val END_TONE_HOLD_MILLIS = 1500L
        private const val WAKE_LOCK_MARGIN_MILLIS = 5000L
        private const val WAKE_LOCK_TAG = "perennia:rest_timer"
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
        private const val EXTRA_ALERT_VOLUME = "alertVolume"

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
            // A Dart double arrives as a Double, so never cast this to Float.
            val alertVolume = (arguments[EXTRA_ALERT_VOLUME] as? Number)?.toFloat() ?: 1f

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
                putExtra(EXTRA_ALERT_VOLUME, alertVolume)
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
