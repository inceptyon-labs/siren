import Foundation

/// UserDefaults keys for Siren's own settings.
enum SirenSettings {
  /// Covers sketch in and ink as you listen (every cover in the app).
  static let coverReveal = "siren.covers.reveal"
  /// What the full player shows: a `PlayerArt` raw value.
  static let playerArt = "siren.player.art"
  static let goalUnit = "siren.goal.unit"
  static let bookGoal = "siren.goal.books"
  static let hourGoal = "siren.goal.hours"
  static let goalOnHome = "siren.goal.onHome"
  /// Bluetooth and car audio outputs that open car mode when they connect (port names).
  static let carDevices = "siren.car.devices"
}
