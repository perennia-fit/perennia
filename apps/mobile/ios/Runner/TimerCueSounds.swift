import AVFoundation
import UIKit

/// Plays a rest's cues in the app: the cue's tone, ducking other audio, and its
/// haptic. Used while the lifter can see the app; the timer notifications cover
/// every other moment.
///
/// The tones load from the bundle root: Xcode flattens the Sounds group when it
/// copies resources, as `UNNotificationSoundName` also expects.
final class TimerCueSounds: NSObject, AVAudioPlayerDelegate {
  private static let toneFiles = [
    "getReady": "GetReady",
    "countdown": "PrepareBeep",
    "end": "TimerComplete",
  ]

  private var players: [String: AVAudioPlayer] = [:]

  func prepare() {
    for (cue, file) in Self.toneFiles where players[cue] == nil {
      guard
        let url = Bundle.main.url(forResource: file, withExtension: "caf"),
        let player = try? AVAudioPlayer(contentsOf: url)
      else {
        continue
      }
      player.delegate = self
      player.prepareToPlay()
      players[cue] = player
    }
  }

  /// Plays the cue's tone and haptic. An unknown cue is ignored.
  func play(cue: String, volume: Float) {
    switch cue {
    case "getReady":
      playTone(cue, volume: volume)
      impact(.medium)
    case "countdown":
      playTone(cue, volume: volume)
      impact(.light)
    case "tick":
      impact(.light)
    case "end":
      playTone(cue, volume: volume)
      impact(.heavy)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        self.impact(.heavy)
      }
    default:
      break
    }
  }

  private func playTone(_ cue: String, volume: Float) {
    guard let player = players[cue] else { return }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
    try? session.setActive(true)
    player.volume = min(max(volume, 0), 1)
    player.currentTime = 0
    if !player.play() {
      deactivateSessionIfIdle()
    }
  }

  private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
  }

  // Other audio stays ducked until the session deactivates, and deactivating
  // while a tone plays would cut it off.
  private func deactivateSessionIfIdle() {
    guard !players.values.contains(where: { $0.isPlaying }) else { return }
    try? AVAudioSession.sharedInstance().setActive(
      false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - AVAudioPlayerDelegate

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    deactivateSessionIfIdle()
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    deactivateSessionIfIdle()
  }
}
