import Foundation
import SwiftUI

struct SirenProgressArtSettingsView: View {
  @AppStorage(SirenSettings.coverReveal) private var revealsProgress = true
  @AppStorage(SirenSettings.coverWash) private var washesCovers = false
  @AppStorage(SirenSettings.playerArt) private var playerArt: PlayerArt = .cover
  @AppStorage(SirenSettings.goalUnit) private var goalUnit: SirenGoalUnit = .books
  @AppStorage(SirenSettings.bookGoal) private var bookGoal = 20
  @AppStorage(SirenSettings.hourGoal) private var hourGoal = 150
  @AppStorage(SirenSettings.goalOnHome) private var showGoalOnHome = true
  @State private var showingTour = false

  var body: some View {
    List {
      Section {
        choiceRow("Plain", detail: "Just the cover", isSelected: !revealsProgress) {
          RevealCover(book: Demo.saltRoad, progress: 1)
        } action: {
          revealsProgress = false
        }
        choiceRow(
          "Ink in as you listen",
          detail: "The sketch fills with colour",
          isSelected: revealsProgress && !washesCovers
        ) {
          RevealCover(book: Demo.saltRoad, progress: 0.57, wash: false)
        } action: {
          revealsProgress = true
          washesCovers = false
        }
        choiceRow(
          "Ink in over a colour wash",
          detail: "The sketch keeps a hint of the cover",
          isSelected: revealsProgress && washesCovers
        ) {
          RevealCover(book: Demo.saltRoad, progress: 0.57, wash: true)
        } action: {
          revealsProgress = true
          washesCovers = true
        }
      } header: {
        Text("Covers")
      } footer: {
        Text("Every cover in the app. Only you see your progress.")
      }

      Section {
        ForEach(playerChoices) { choice in
          choiceRow(choice.label, detail: choice.detail, isSelected: playerArt == choice) {
            preview(for: choice)
          } action: {
            playerArt = choice
          }
        }
      } header: {
        Text("Player")
      } footer: {
        switch playerArt {
        case .cover: Text("What the full player shows above the controls.")
        case .map: Text("The full player opens on the map; swipe the art for the cover.")
        case .voice:
          Text(
            "The full player opens on the voice print, drawn from the book's audio, for downloaded books. Streamed books show the cover."
          )
        }
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

      Section {
        Button("Show the Welcome Tour") { showingTour = true }
          .listRowBackground(SirenTheme.raised)
      }
    }
    .fullScreenCover(isPresented: $showingTour) {
      SirenTour(ending: .done)
        .displayScaled()
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .tint(SirenTheme.tint)
    .navigationTitle("Progress Art")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func choiceRow<Preview: View>(
    _ title: LocalizedStringKey,
    detail: LocalizedStringKey,
    isSelected: Bool,
    @ViewBuilder preview: () -> Preview,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        preview()
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.body)
            .foregroundStyle(SirenTheme.ink)
          Text(detail)
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        Spacer(minLength: 8)
        if isSelected {
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
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private func preview(for choice: PlayerArt) -> some View {
    switch choice {
    case .cover:
      RevealCover(book: Demo.saltRoad, progress: revealsProgress ? 0.57 : 1)
    case .map:
      // Crop toward the inked island so the fog edge stays in frame.
      thumbnail(
        Image("SirenDemoMapSaltRoad")
          .resizable()
          .scaledToFill()
          .frame(width: 84, height: 84)
          .frame(width: 56, height: 56, alignment: .leading)
      )
    case .voice:
      thumbnail(SirenVoicePrintThumbnail())
    }
  }

  /// Same corner, hairline and shadow as RevealCover, for the two non-cover previews.
  private func thumbnail<Content: View>(_ content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: SirenTheme.coverRadius, style: .continuous)
    return
      content
      .frame(width: 56, height: 56)
      .clipShape(shape)
      .overlay { shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
      .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }

  private var playerChoices: [PlayerArt] { PlayerArt.allCases }

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
          style: StrokeStyle(lineWidth: 1, lineJoin: .round)
        )
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

enum SirenGoalUnit: String, Hashable {
  case books, hours
}

#Preview {
  NavigationStack {
    SirenProgressArtSettingsView()
  }
}
