import Foundation

enum SirenFormat {
  /// 12:28, or 1:02:28 past an hour.
  static func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let rest = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, rest)
      : String(format: "%d:%02d", minutes, rest)
  }

  /// 6h 12m, or 42m under an hour.
  static func span(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }

  /// 1.3×
  static func speed(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
  }
}
