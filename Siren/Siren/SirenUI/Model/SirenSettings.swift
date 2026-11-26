import Foundation

/// UserDefaults keys for Siren's own settings.
enum SirenSettings {
  /// Covers sketch in and ink as you listen (every cover in the app).
  static let coverReveal = "siren.covers.reveal"
  /// Sketches carry a faint wash of the cover's colors (with the reveal on).
  static let coverWash = "siren.covers.wash"
  /// What the full player shows: a `PlayerArt` raw value.
  static let playerArt = "siren.player.art"
  static let goalUnit = "siren.goal.unit"
  static let bookGoal = "siren.goal.books"
  static let hourGoal = "siren.goal.hours"
  static let goalOnHome = "siren.goal.onHome"
  /// Bluetooth and car audio outputs that open car mode when they connect (port names).
  static let carDevices = "siren.car.devices"
  /// Profiles (connection IDs) that ask for Face ID before switching to them.
  static let lockedProfiles = "siren.profiles.locked"
  /// Profiles that open the assisted player and ask for Face ID before switching away.
  static let kidsProfiles = "siren.profiles.kids"
  /// The profile to return to if a Face ID check for a switch doesn't pass (set while it's open).
  static let pendingProfileCheck = "siren.profiles.pendingCheck"
  /// Library books sorted by Audible rating, highest first.
  static let sortByRating = "siren.library.sortByRating"
  /// Library books rated at least this on Audible (0 for any).
  static let minimumRating = "siren.library.minimumRating"
  /// Voice boost on the player: less rumble, clearer words, an even level.
  static let voiceBoost = "siren.player.voiceBoost"
  /// Trim silence on the player (downloaded books).
  static let trimSilence = "siren.player.trimSilence"
  /// Listening time trim silence has saved, in seconds.
  static let trimSilenceSaved = "siren.player.trimSilenceSaved"
  /// "Previously on" recaps when you come back to a book (on unless turned off).
  static let recaps = "siren.player.recaps"
  /// The welcome tour has been seen (or skipped) on this device.
  static let tourSeen = "siren.tour.seen"
}
