import AVFoundation
import SwiftUI

/// The "Previously on" card over the player's art, with the recap read aloud on request.
struct SirenRecapCard: View {
  let recap: SirenRecaps.Recap
  @State private var speaker = SirenRecapSpeaker.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Previously on \(recap.title)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(1)
        Spacer(minLength: 8)
        Button("Close", systemImage: "xmark") {
          speaker.stop()
          SirenRecaps.shared.dismiss()
        }
        .labelStyle(.iconOnly)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary)
      }
      // As tall as the text, up to 220 pt, then it scrolls.
      ScrollView { summary }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
      Button(
        speaker.isSpeaking ? "Stop Reading" : "Read Aloud",
        systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2"
      ) {
        if speaker.isSpeaking {
          speaker.stop()
        } else {
          speaker.speak(recap.summaries.joined(separator: " "), language: recap.language)
        }
      }
      .buttonStyle(RequestSearchCapsuleStyle(filled: false))
    }
    .padding(16)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    // The player is dark in either appearance.
    .environment(\.colorScheme, .dark)
    .onDisappear { speaker.stop() }
  }

  private var summary: some View {
    Text(recap.summaries.joined(separator: "\n\n"))
      .font(.callout)
      .foregroundStyle(SirenTheme.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// Reads a recap aloud, pausing the book while it does and resuming it after.
@MainActor @Observable
final class SirenRecapSpeaker: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = SirenRecapSpeaker()

  private(set) var isSpeaking = false
  @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
  @ObservationIgnored private var resumesBook = false

  override private init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String, language: String?) {
    if let player = PlayerManager.shared.current, player.isPlaying {
      player.onPauseTapped()
      resumesBook = true
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = BookLanguage.code(for: language).flatMap { AVSpeechSynthesisVoice(language: $0) }
    isSpeaking = true
    synthesizer.speak(utterance)
  }

  func stop() {
    guard isSpeaking else { return }
    synthesizer.stopSpeaking(at: .immediate)
  }

  private func finished() {
    isSpeaking = false
    if resumesBook { PlayerManager.shared.current?.onPlayTapped() }
    resumesBook = false
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in finished() }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor in finished() }
  }
}
