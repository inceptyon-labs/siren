import SwiftUI
import UIKit

enum SirenTheme {
  static let ground = Color(sirenLight: 0xEAE9E5, dark: 0x111316)
  static let raised = Color(sirenLight: 0xFFFFFF, dark: 0x1C1F24)
  static let ink = Color(sirenLight: 0x16181D, dark: 0xF2F2F0)
  static let secondary = Color(sirenLight: 0x5E6470, dark: 0xA3A8B2)
  static let separator = Color(sirenLight: 0xE3E3E6, dark: 0x2C3037)
  static let tint = Color(sirenLight: 0x0C7480, dark: 0x3FB6BF)
  /// Section headings: a deep sea ink, darker than the tint so it never reads as a button.
  static let heading = Color(sirenLight: 0x17474E, dark: 0xA9D6D9)
  static let tintWash = Color(sirenLight: 0xE2F1F2, dark: 0x16343A)
  static let onTint = Color(sirenLight: 0xFFFFFF, dark: 0x111316)

  static let paper = Color(sirenHex: 0xECEAE4)
  static let graphite = Color(sirenHex: 0x55585E)

  static let coverRadius: CGFloat = 6
  static let rowRadius: CGFloat = 14
}

enum SirenType {
  /// Book titles. Everything else is SF Pro, except the few `display` places.
  static func bookTitle(_ style: Font.TextStyle) -> Font {
    .system(style, design: .serif).weight(.semibold)
  }

  /// New York for Home's section headings, the goal count and Resume, as in the approved Home.
  static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
    .system(style, design: .serif).weight(weight)
  }
}

extension Color {
  init(sirenHex hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }

  init(sirenLight light: UInt32, dark: UInt32) {
    self.init(
      UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((hex >> 16) & 0xFF) / 255,
          green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255,
          alpha: 1
        )
      }
    )
  }
}
