import SwiftUI

struct PreferenceRow: View {
  let systemImage: String
  let tint: Color
  let title: Text
  let subtitle: Text?

  init(
    systemImage: String,
    tint: Color,
    title: Text,
    subtitle: Text? = nil
  ) {
    self.systemImage = systemImage
    self.tint = tint
    self.title = title
    self.subtitle = subtitle
  }

  init(
    systemImage: String,
    tint: Color,
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil
  ) {
    self.init(
      systemImage: systemImage,
      tint: tint,
      title: Text(title),
      subtitle: subtitle.map { Text($0) }
    )
  }

  var body: some View {
    // SIREN: neutral glyphs and Siren's row type in place of colored tiles (`tint` is unused)
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.body)
        .foregroundStyle(SirenTheme.secondary)
        .frame(width: 26)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        title
          .font(.body)
          .foregroundStyle(SirenTheme.ink)

        if let subtitle {
          subtitle
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }
}
