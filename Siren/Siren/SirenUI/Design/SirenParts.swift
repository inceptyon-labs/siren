import SwiftUI

/// A household member's fixed furniture: same plate color and initial everywhere.
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
          .fixedSize()
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      count > 0 ? "Rated \(rating, specifier: "%.1f") from \(count) ratings" : "Rated \(rating, specifier: "%.1f")"
    )
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
