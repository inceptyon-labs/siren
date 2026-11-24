import Foundation
import SwiftUI

/// Phone on a car mount, read at arm's length over Bluetooth. Always dark, no tab bar.
struct SirenCarModeView: View {
  var onClose: () -> Void

  private let book = Demo.saltRoad
  private let speeds: [Double] = [1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0]

  @State private var isPlaying = true
  @State private var speedIndex = 3
  @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 38
  @ScaledMetric(relativeTo: .largeTitle) private var playGlyph: CGFloat = 60

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      topBar
      nowPlaying
        .padding(.top, 16)
      chapterClock
        .padding(.top, 20)
      Spacer(minLength: 20)
      controls
        .layoutPriority(1)
      footer
        .padding(.top, 14)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(SirenTheme.ground)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .environment(\.colorScheme, .dark)
    .preferredColorScheme(.dark)
  }

  private var topBar: some View {
    HStack {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.title2.weight(.semibold))
          .foregroundStyle(SirenTheme.ink)
          .frame(width: 56, height: 56)
          .background(SirenTheme.raised, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close car mode")

      Spacer(minLength: 12)

      Label("Model Y", systemImage: "car.fill")
        .font(.headline)
        .foregroundStyle(SirenTheme.secondary)
        .accessibilityLabel("Playing on Model Y")
    }
  }

  private var nowPlaying: some View {
    HStack(spacing: 16) {
      RevealCover(book: book, shadow: false)
        .frame(width: 96, height: 96)
      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(SirenType.bookTitle(.title2))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(2)
        Text("Ch \(book.currentChapter) · \(book.chapterTitle)")
          .font(.headline)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(2)
          .accessibilityLabel("Chapter \(book.currentChapter), \(book.chapterTitle)")
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The one big number on the screen: a measurement, so it gets a fixed size.
  private var chapterClock: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(book.chapterRemaining)
        .font(.system(size: 96, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text("left in chapter")
        .font(.title3)
        .foregroundStyle(SirenTheme.secondary)
      ProgressView(value: book.chapterProgress)
        .tint(SirenTheme.tint)
        .padding(.top, 16)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(spokenRemaining) left in chapter")
  }

  private var controls: some View {
    GeometryReader { proxy in
      let gap: CGFloat = 12
      let side = ((proxy.size.width - gap * 2) * 0.3).rounded(.down)
      let center = proxy.size.width - gap * 2 - side * 2
      let lower = min(128, max(100, (proxy.size.height - gap) * 0.4))
      let upper = max(100, proxy.size.height - gap - lower)

      VStack(spacing: gap) {
        HStack(spacing: gap) {
          tile("gobackward.30", label: "Back 30 seconds")
            .frame(width: side, height: upper)
          playTile
            .frame(width: center, height: upper)
          tile("goforward.30", label: "Forward 30 seconds")
            .frame(width: side, height: upper)
        }
        HStack(spacing: gap) {
          tile("backward.end.fill", label: "Previous chapter")
            .frame(width: side, height: lower)
          speedTile
            .frame(width: center, height: lower)
          tile("forward.end.fill", label: "Next chapter")
            .frame(width: side, height: lower)
        }
      }
    }
    .frame(minHeight: 224, maxHeight: 340)
  }

  private func tile(_ symbol: String, label: LocalizedStringKey) -> some View {
    Button {
    } label: {
      Image(systemName: symbol)
        .font(.system(size: min(glyph, 56), weight: .semibold))
        .foregroundStyle(SirenTheme.ink)
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.raised))
    .accessibilityLabel(label)
  }

  private var playTile: some View {
    Button {
      isPlaying.toggle()
    } label: {
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .font(.system(size: min(playGlyph, 88), weight: .bold))
        .foregroundStyle(SirenTheme.onTint)
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.tint))
    .accessibilityLabel(isPlaying ? "Pause" : "Play")
  }

  private var speedTile: some View {
    Button {
      speedIndex = (speedIndex + 1) % speeds.count
    } label: {
      Text(speedText)
        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(SirenTheme.ink)
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.raised))
    .accessibilityLabel("Playback speed")
    .accessibilityValue("\(speeds[speedIndex].formatted()) times")
  }

  private var footer: some View {
    Label("Screen stays on", systemImage: "sun.max")
      .font(.footnote)
      .foregroundStyle(SirenTheme.secondary)
      .frame(maxWidth: .infinity)
  }

  private var speedText: String {
    "\(speeds[speedIndex].formatted(.number.precision(.fractionLength(1...2))))×"
  }

  /// "18:42" read aloud as "18 minutes, 42 seconds".
  private var spokenRemaining: String {
    let seconds = book.chapterRemaining.split(separator: ":").compactMap { Int($0) }
      .reduce(0) { $0 * 60 + $1 }
    return Duration.seconds(seconds)
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
  }
}

private struct SirenCarTileStyle: ButtonStyle {
  let fill: Color

  @Environment(\.accessibilityReduceMotion) var reduceMotion
  let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(fill, in: shape)
      .contentShape(shape)
      .opacity(configuration.isPressed ? 0.75 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

#Preview {
  SirenCarModeView(onClose: {})
}
