import AVFoundation
import Combine

/// Voice boost: cuts the rumble under a voice (road and engine noise), lifts the range that makes
/// words clear and evens out the level. It runs on the equalizer's audio tap, on top of the
/// equalizer when that's on, and applies to every book.
enum SirenVoiceBoost {
  static var isOn: Bool { UserDefaults.standard.bool(forKey: SirenSettings.voiceBoost) }

  /// The setting now, then each change, on the main queue.
  static var changes: AnyPublisher<Bool, Never> {
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .map { _ in isOn }
      .prepend(isOn)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .eraseToAnyPublisher()
  }

  /// Bands added after the equalizer's own: a high-pass under the voice, then a presence lift.
  static let bandCount = 2

  /// At least this much leveling while it's on.
  static let leveling = LevelingStrength.medium

  static func configure(_ bands: [AVAudioUnitEQFilterParameters]) {
    guard bands.count == bandCount else { return }
    bands[0].filterType = .highPass
    bands[0].frequency = 100
    bands[1].filterType = .parametric
    bands[1].frequency = 3000
    bands[1].bandwidth = 1.5
    bands[1].gain = 4
  }
}
