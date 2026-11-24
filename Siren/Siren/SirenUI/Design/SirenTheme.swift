import SwiftUI
import UIKit

enum SirenTheme {
  static let ground = Color(sirenLight: 0xF5F5F3, dark: 0x111316)
  static let raised = Color(sirenLight: 0xFFFFFF, dark: 0x1C1F24)
  static let ink = Color(sirenLight: 0x16181D, dark: 0xF2F2F0)
  static let secondary = Color(sirenLight: 0x5E6470, dark: 0xA3A8B2)
  static let separator = Color(sirenLight: 0xE3E3E6, dark: 0x2C3037)
  static let tint = Color(sirenLight: 0x0C7480, dark: 0x3FB6BF)
  static let tintWash = Color(sirenLight: 0xE2F1F2, dark: 0x16343A)
  static let onTint = Color(sirenLight: 0xFFFFFF, dark: 0x111316)

  static let paper = Color(sirenHex: 0xECEAE4)
  static let graphite = Color(sirenHex: 0x55585E)

  static let coverRadius: CGFloat = 6
  static let rowRadius: CGFloat = 14
}

enum SirenType {
  /// Book titles only. Everything else is SF Pro.
  static func bookTitle(_ style: Font.TextStyle) -> Font {
    .system(style, design: .serif).weight(.semibold)
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

/// A household member's fixed furniture: same plate colour and initial everywhere.
struct HouseholdPlate: View {
  let member: DemoMember
  var size: CGFloat = 28

  var body: some View {
    Text(member.initial)
      .font(.system(size: size * 0.46, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(member.color, in: Circle())
      .accessibilityLabel(member.name)
  }
}

struct StarRating: View {
  let rating: Double
  let count: Int
  var compact = false

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "star.fill")
        .font(.caption2)
        .foregroundStyle(Color(sirenLight: 0xB7791F, dark: 0xE9B65A))
      Text(rating, format: .number.precision(.fractionLength(1)))
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SirenTheme.ink)
      if !compact {
        Text("(\(count.formatted()))")
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Rated \(rating, specifier: "%.1f") from \(count) ratings")
  }
}

/// Plain section title, Apple Music / Books style.
struct SirenSectionHeader: View {
  let title: String
  var action: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(SirenTheme.ink)
      Spacer()
      if let action {
        Button(action) {}
          .font(.subheadline)
      }
    }
    .padding(.top, 8)
  }
}
