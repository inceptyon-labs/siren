import Foundation
import SwiftUI

struct SirenProgressArtSettingsView: View {
  @State private var style: SirenArtStyleChoice = .coverReveal
  @State private var showInPlayer = true
  @State private var showOnFinishedShelf = true
  @State private var goalUnit: SirenGoalUnit = .books
  @State private var bookGoal = 20
  @State private var hourGoal = 150
  @State private var showGoalOnHome = true

  var body: some View {
    List {
      Section {
        ForEach(SirenArtStyleChoice.allCases) { choice in
          styleRow(choice)
        }
      } header: {
        Text("Style")
      } footer: {
        Text("Art fills in as you listen. Only you see it.")
      }

      Section("Show art") {
        Toggle("In the player", isOn: $showInPlayer)
          .foregroundStyle(SirenTheme.ink)
          .listRowBackground(SirenTheme.raised)
        Toggle("Finished books shelf", isOn: $showOnFinishedShelf)
          .foregroundStyle(SirenTheme.ink)
          .listRowBackground(SirenTheme.raised)
      }

      Section("Yearly goal") {
        Stepper(value: goalValue, in: goalRange, step: goalUnit == .books ? 1 : 10) {
          HStack {
            Text("Goal")
              .foregroundStyle(SirenTheme.ink)
            Spacer(minLength: 8)
            Text(goalText)
              .foregroundStyle(SirenTheme.secondary)
              .monospacedDigit()
          }
        }
        .listRowBackground(SirenTheme.raised)

        Picker("Count goal in", selection: $goalUnit) {
          Text("Books").tag(SirenGoalUnit.books)
          Text("Hours").tag(SirenGoalUnit.hours)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowBackground(SirenTheme.raised)

        Toggle("Show on Home", isOn: $showGoalOnHome)
          .foregroundStyle(SirenTheme.ink)
          .listRowBackground(SirenTheme.raised)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .tint(SirenTheme.tint)
    .navigationTitle("Progress Art")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func styleRow(_ choice: SirenArtStyleChoice) -> some View {
    Button {
      style = choice
    } label: {
      HStack(spacing: 14) {
        preview(for: choice)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(choice.title)
            .font(.body)
            .foregroundStyle(SirenTheme.ink)
          Text(choice.detail)
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        Spacer(minLength: 8)
        if style == choice {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(SirenTheme.tint)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
    .listRowBackground(SirenTheme.raised)
    .accessibilityAddTraits(style == choice ? .isSelected : [])
  }

  @ViewBuilder
  private func preview(for choice: SirenArtStyleChoice) -> some View {
    switch choice {
    case .off:
      RevealCover(book: Demo.saltRoad, progress: 1)
        .frame(width: 56, height: 56)
    case .coverReveal:
      RevealCover(book: Demo.saltRoad, progress: 0.57)
        .frame(width: 56, height: 56)
    case .map:
      // Crop toward the inked island so the fog edge stays in frame.
      thumbnail(
        Image("SirenDemoMapSaltRoad")
          .resizable()
          .scaledToFill()
          .frame(width: 84, height: 84)
          .frame(width: 56, height: 56, alignment: .leading)
      )
    case .voicePrint:
      thumbnail(SirenVoicePrintThumbnail())
    }
  }

  /// Same corner, hairline and shadow as RevealCover, for the two non-cover previews.
  private func thumbnail<Content: View>(_ content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: SirenTheme.coverRadius, style: .continuous)
    return content
      .frame(width: 56, height: 56)
      .clipShape(shape)
      .overlay { shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
      .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }

  private var goalValue: Binding<Int> {
    goalUnit == .books ? $bookGoal : $hourGoal
  }

  private var goalRange: ClosedRange<Int> {
    goalUnit == .books ? 1...200 : 10...2000
  }

  private var goalText: String {
    switch goalUnit {
    case .books:
      bookGoal == 1 ? String(localized: "1 book") : String(localized: "\(bookGoal) books")
    case .hours:
      String(localized: "\(hourGoal) hours")
    }
  }
}

/// Nine stacked ridgelines, white on the player's dark ground; the first five are heard.
private struct SirenVoicePrintThumbnail: View {
  var body: some View {
    let ridges = Self.ridges
    Canvas { context, size in
      let ground = Color(sirenHex: 0x111316)
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
      for (index, ridge) in ridges.enumerated() {
        var line = Path()
        line.addLines(ridge.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
        var occluder = line
        occluder.addLine(to: CGPoint(x: size.width + 2, y: size.height))
        occluder.addLine(to: CGPoint(x: -2, y: size.height))
        occluder.closeSubpath()
        context.fill(occluder, with: .color(ground))
        context.stroke(
          line,
          with: .color(index < 5 ? Color.white : Color.white.opacity(0.3)),
          style: StrokeStyle(lineWidth: 1, lineJoin: .round))
      }
    }
  }

  /// Ridge points in unit space, seeded from the demo book so the preview never changes.
  private static let ridges: [[CGPoint]] = {
    var random = SeededRandom(seed: UInt64(truncatingIfNeeded: Demo.saltRoad.id.sirenSeed))
    let samples = 24
    return (0..<9).map { ridge in
      let baseline = 0.2 + Double(ridge) * 0.085
      return (0...samples).map { step in
        let t = Double(step) / Double(samples)
        let d = (t - 0.5) / 0.18
        let envelope = exp(-d * d)
        let noise = random.next()
        let lift = envelope * (0.04 + noise * 0.12) + noise * 0.01
        return CGPoint(x: -0.02 + t * 1.04, y: baseline - lift)
      }
    }
  }()
}

private enum SirenArtStyleChoice: CaseIterable, Identifiable {
  case off, coverReveal, map, voicePrint

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .off: "Off"
    case .coverReveal: "Cover reveal"
    case .map: "Map"
    case .voicePrint: "Voice print"
    }
  }

  var detail: LocalizedStringKey {
    switch self {
    case .off: "Just the cover"
    case .coverReveal: "The sketch fills with colour"
    case .map: "Fog lifts along your route"
    case .voicePrint: "A ridge for every chapter"
    }
  }
}

private enum SirenGoalUnit: Hashable {
  case books, hours
}

#Preview {
  NavigationStack {
    SirenProgressArtSettingsView()
  }
}
