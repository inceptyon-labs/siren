import AVFoundation
import Combine

/// Trim silence: shortens the long pauses in downloaded books by jumping through them, using the
/// pauses `SirenAudioScan` finds ahead of where you're listening. A jump restarts the sound after
/// about 0.16 s (0.9 s while the equalizer or voice boost is on, which run on an audio tap), so only
/// pauses long enough to come out ahead are trimmed. Streamed books play as they are: the player
/// can't see far enough ahead in them to cut a pause without clipping the next word.
@MainActor
final class SirenTrimSilence {
  static var isOn: Bool { UserDefaults.standard.bool(forKey: SirenSettings.trimSilence) }

  /// The setting now, then each change, on the main queue.
  static var changes: AnyPublisher<Bool, Never> {
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .map { _ in isOn }
      .prepend(isOn)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .eraseToAnyPublisher()
  }

  /// Listening time trim silence has saved, in seconds, across every book.
  static var saved: Double { UserDefaults.standard.double(forKey: SirenSettings.trimSilenceSaved) }

  /// Silence kept at the start of a pause, and before the next word, in the book's time.
  private static let keepStart = 0.3
  private static let keepEnd = 0.25
  /// How long the sound takes to restart after a jump, without and with an audio tap.
  private static let restart = 0.16
  private static let restartWithTap = 0.9

  private weak var player: AVQueuePlayer?
  private var timer: Timer?
  private var isJumping = false
  private var heldUntil = Date.distantPast
  private var unsaved = 0.0

  init(player: AVQueuePlayer) {
    self.player = player
  }

  func setEnabled(_ on: Bool) {
    timer?.invalidate()
    timer = nil
    guard on else { return save() }
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        guard let self else { return timer.invalidate() }
        self.step()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// A seek of your own: no jump for a moment, so it isn't cancelled by one.
  func hold() {
    heldUntil = Date(timeIntervalSinceNow: 1)
  }

  private func step() {
    guard let player, player.timeControlStatus == .playing else { return save() }
    guard !isJumping, Date() >= heldUntil, let item = player.currentItem,
      let file = (item.asset as? AVURLAsset)?.url, file.isFileURL
    else { return }
    let time = item.currentTime().seconds
    guard time.isFinite else { return }
    SirenAudioScan.shared.scan(file, from: time)
    guard let pause = SirenAudioScan.shared.pause(in: file, at: time), time >= pause.lowerBound + Self.keepStart
    else { return }
    let restart = item.audioMix == nil ? Self.restart : Self.restartWithTap
    let target = pause.upperBound - Self.keepEnd
    // The jump is in the book's seconds; the restart is real time.
    let rate = Double(max(player.defaultRate, 0.1))
    let jump = target - time
    let saving = jump / rate - restart
    guard saving >= 0.3 else { return }

    isJumping = true
    item.seek(to: CMTime(seconds: target, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) {
      finished in
      Task { @MainActor [weak self] in
        guard let self else { return }
        isJumping = false
        guard finished else { return }
        unsaved += saving
        if unsaved >= 5 { save() }
      }
    }
  }

  private func save() {
    guard unsaved > 0 else { return }
    UserDefaults.standard.set(Self.saved + unsaved, forKey: SirenSettings.trimSilenceSaved)
    unsaved = 0
  }
}
