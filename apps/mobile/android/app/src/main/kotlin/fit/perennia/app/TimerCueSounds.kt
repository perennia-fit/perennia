package fit.perennia.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Plays a rest's cues in the app: the cue's tone, ducking other audio, and its
 * vibration. Used while the lifter can see the app; the notifications in
 * [TimerForegroundService] cover every other moment.
 *
 * The tones are named through `R.raw`, never `getIdentifier`. A release build
 * shrinks resources, and the notification channels' by-name sound URIs are
 * invisible to the shrinker, so these references are what keep the three files
 * in the APK for both this class and the channels.
 */
class TimerCueSounds(context: Context) {
    private class Tone(val player: MediaPlayer) {
        var prepared = false
    }

    private val appContext = context.applicationContext
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }
    private val focusRequest: AudioFocusRequest? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(audioAttributes)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
        } else {
            null
        }
    private val tones = mutableMapOf<String, Tone>()

    /** Loads the tones off the main thread, so a cue never waits on a load. */
    fun prepare() {
        for ((cue, resId) in CUE_TONES) {
            if (cue !in tones) {
                buildTone(resId)?.let { tones[cue] = it }
            }
        }
    }

    /** Plays [cue]'s tone and vibration. An unknown cue is ignored. */
    fun play(cue: String, volume: Float) {
        val pattern = CUE_VIBRATIONS[cue] ?: return
        if (cue in CUE_TONES) {
            playTone(cue, volume.coerceIn(0f, 1f))
        }
        vibrate(pattern)
    }

    fun release() {
        for (tone in tones.values) {
            tone.player.release()
        }
        tones.clear()
        abandonFocus()
    }

    private fun buildTone(resId: Int): Tone? {
        val file = appContext.resources.openRawResourceFd(resId) ?: return null
        val player = MediaPlayer()
        val tone = Tone(player)
        return try {
            player.setAudioAttributes(audioAttributes)
            player.setDataSource(file.fileDescriptor, file.startOffset, file.length)
            player.setOnPreparedListener { tone.prepared = true }
            player.setOnCompletionListener { abandonFocusIfIdle() }
            player.setOnErrorListener { _, _, _ ->
                tone.prepared = false
                abandonFocusIfIdle()
                true
            }
            player.prepareAsync()
            tone
        } catch (_: Exception) {
            // A tone that won't load must not stop the vibration or the rest.
            player.release()
            null
        } finally {
            file.close()
        }
    }

    private fun playTone(cue: String, volume: Float) {
        val tone = tones[cue]?.takeIf { it.prepared } ?: return
        // Denied while, say, a phone call holds focus: that audio goes first.
        if (!requestFocus()) {
            return
        }
        tone.player.setVolume(volume, volume)
        tone.player.seekTo(0)
        tone.player.start()
    }

    private fun requestFocus(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioManager.requestAudioFocus(focusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocusIfIdle() {
        if (tones.values.none { it.prepared && it.player.isPlaying }) {
            abandonFocus()
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioManager.abandonAudioFocusRequest(focusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun vibrate(pattern: LongArray) {
        val vibrator = vibrator()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun vibrator(): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = appContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    private companion object {
        val CUE_TONES = mapOf(
            "getReady" to R.raw.get_ready,
            "countdown" to R.raw.prepare_beep,
            "end" to R.raw.timer_complete,
        )

        // Off, then on, then off...: the first value is the wait before the
        // first pulse.
        val CUE_VIBRATIONS = mapOf(
            "getReady" to longArrayOf(0L, 80L),
            "countdown" to longArrayOf(0L, 40L),
            "tick" to longArrayOf(0L, 40L),
            "end" to longArrayOf(0L, 200L, 150L, 200L),
        )
    }
}
