import Foundation
import SwiftUI

/// Phone on a car mount, read at arm's length over Bluetooth. Always dark, no tab bar.
struct SirenCarModeView: View {
  let book: SirenBook
  let playback: SirenPlayback
  /// The Bluetooth or car output playing now, such as "Model Y".
  var deviceName: String?
  /// Whether car mode opens by itself when `deviceName` connects; nil hides the choice.
  var opensAutomatically: Binding<Bool>?
  var onClose: () -> Void

  @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 38
  @ScaledMetric(relativeTo: .largeTitle) private var playGlyph: CGFloat = 60

  private var hasChapters: Bool { book.chapterCount > 1 && !book.chapterRemaining.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      topBar
      nowPlaying
        .padding(.top, 16)
      clock
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

      if let deviceName {
        if let opensAutomatically {
          Menu {
            Toggle("Open Car Mode When \(deviceName) Connects", isOn: opensAutomatically)
          } label: {
            deviceLabel(deviceName, showsChevron: true)
          }
          .accessibilityLabel("Playing on \(deviceName)")
          .accessibilityHint("Choose whether car mode opens when it connects")
        } else {
          deviceLabel(deviceName, showsChevron: false)
            .accessibilityLabel("Playing on \(deviceName)")
        }
      }
    }
  }

  private func deviceLabel(_ name: String, showsChevron: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "car.fill")
      Text(name)
        .lineLimit(1)
      if showsChevron {
        Image(systemName: "chevron.down")
          .font(.caption.weight(.bold))
      }
    }
    .font(.headline)
    .foregroundStyle(SirenTheme.secondary)
    .frame(minHeight: 44)
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
        Group {
          if hasChapters {
            Text("Ch \(book.currentChapter) · \(book.chapterTitle)")
              .accessibilityLabel("Chapter \(book.currentChapter), \(book.chapterTitle)")
          } else {
            Text(book.author)
          }
        }
        .font(.headline)
        .foregroundStyle(SirenTheme.secondary)
        .lineLimit(2)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The one big number on the screen: a measurement, so it gets a fixed size.
  private var clock: some View {
    let remaining = hasChapters ? book.chapterRemaining : playback.remaining
    return VStack(alignment: .leading, spacing: 0) {
      Text(remaining)
        .font(.system(size: 96, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text(hasChapters ? "left in chapter" : "left in book")
        .font(.title3)
        .foregroundStyle(SirenTheme.secondary)
      ProgressView(value: hasChapters ? book.chapterProgress : playback.position)
        .tint(SirenTheme.tint)
        .padding(.top, 16)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      hasChapters ? "\(spoken(remaining)) left in chapter" : "\(spoken(remaining)) left in book"
    )
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
          tile(
            "gobackward.\(playback.skipBack)",
            label: "Back \(playback.skipBack) seconds",
            action: playback.onSkipBack
          )
          .frame(width: side, height: upper)
          playTile
            .frame(width: center, height: upper)
          tile(
            "goforward.\(playback.skipForward)",
            label: "Forward \(playback.skipForward) seconds",
            action: playback.onSkipForward
          )
          .frame(width: side, height: upper)
        }
        HStack(spacing: gap) {
          tile("backward.end.fill", label: "Previous chapter", action: playback.onPreviousChapter)
            .disabled(!playback.canGoPreviousChapter)
            .frame(width: side, height: lower)
          speedTile
            .frame(width: center, height: lower)
          tile("forward.end.fill", label: "Next chapter", action: playback.onNextChapter)
            .disabled(!playback.canGoNextChapter)
            .frame(width: side, height: lower)
        }
      }
    }
    .frame(minHeight: 224, maxHeight: 340)
  }

  private func tile(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: min(glyph, 56), weight: .semibold))
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.raised, ink: SirenTheme.ink))
    .accessibilityLabel(label)
  }

  private var playTile: some View {
    Button(action: playback.onTogglePlay) {
      if playback.isLoading {
        ProgressView()
          .controlSize(.large)
          .tint(SirenTheme.onTint)
      } else {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: min(playGlyph, 88), weight: .bold))
      }
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.tint, ink: SirenTheme.onTint))
    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
  }

  private var speedTile: some View {
    Button(action: playback.onSpeed) {
      Text(playback.speed)
        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
        .monospacedDigit()
    }
    .buttonStyle(SirenCarTileStyle(fill: SirenTheme.raised, ink: SirenTheme.ink))
    .accessibilityLabel("Playback speed")
    .accessibilityValue(playback.speed)
    .accessibilityHint("Changes to the next speed")
  }

  private var footer: some View {
    Label("Screen stays on", systemImage: "sun.max")
      .font(.footnote)
      .foregroundStyle(SirenTheme.secondary)
      .frame(maxWidth: .infinity)
  }

  /// "18:42" read aloud as "18 minutes, 42 seconds".
  private func spoken(_ clock: String) -> String {
    let seconds = clock.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    return Duration.seconds(seconds)
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
  }
}

private struct SirenCarTileStyle: ButtonStyle {
  let fill: Color
  let ink: Color

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(ink.opacity(isEnabled ? 1 : 0.3))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(fill, in: shape)
      .contentShape(shape)
      .opacity(configuration.isPressed ? 0.75 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// Car mode over the demo book, with its own play state.
struct SirenCarModeDemo: View {
  var onClose: () -> Void

  private let speeds: [Double] = [1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0]
  @State private var isPlaying = true
  @State private var speedIndex = 3
  @State private var opensAutomatically = true

  var body: some View {
    SirenCarModeView(
      book: Demo.saltRoad,
      playback: SirenPlayback(
        isPlaying: isPlaying,
        speed: SirenFormat.speed(speeds[speedIndex]),
        onTogglePlay: { isPlaying.toggle() },
        onSpeed: { speedIndex = (speedIndex + 1) % speeds.count }
      ),
      deviceName: "Model Y",
      opensAutomatically: $opensAutomatically,
      onClose: onClose
    )
  }
}

#Preview {
  SirenCarModeDemo(onClose: {})
}
