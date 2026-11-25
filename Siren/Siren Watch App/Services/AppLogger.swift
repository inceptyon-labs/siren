import OSLog

enum AppLogger {
  // SIREN: Siren identifiers
  private static let subsystem = Bundle.main.bundleIdentifier ?? "com.inceptyon.siren.watchkitapp"

  static let watchConnectivity = Logger(subsystem: subsystem, category: "watch-connectivity")
  static let player = Logger(subsystem: subsystem, category: "player")
  static let download = Logger(subsystem: subsystem, category: "download")
}
