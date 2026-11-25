import SwiftUI

/// The glass bar above the tab bar: what's playing, play/pause and skip forward.
struct SirenMiniPlayer: View {
  let book: SirenBook
  var isPlaying = true
  var skipForward = 30
  var onTogglePlay: () -> Void = {}
  var onSkipForward: () -> Void = {}
  var onOpen: () -> Void

  private var caption: String {
    if book.chapterCount > 1, !book.chapterRemaining.isEmpty {
      return "Ch \(book.currentChapter) · \(book.chapterRemaining) left"
    }
    return book.timeLeft.isEmpty ? book.author : "\(book.timeLeft) left"
  }

  var body: some View {
    HStack(spacing: 12) {
      RevealCover(book: book, cornerRadius: 4, shadow: false)
        .frame(width: 34, height: 34)
      VStack(alignment: .leading, spacing: 1) {
        Text(book.title)
          .font(SirenType.bookTitle(.subheadline))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(1)
        Text(caption)
          .font(.caption)
          .foregroundStyle(SirenTheme.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Button(action: onTogglePlay) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title3)
      }
      .buttonStyle(.plain)
      .frame(width: 44, height: 44)
      .accessibilityLabel(isPlaying ? "Pause" : "Play")
      Button(action: onSkipForward) {
        Image(systemName: "goforward.\(skipForward)").font(.title3)
      }
      .buttonStyle(.plain)
      .frame(width: 44, height: 44)
      .accessibilityLabel("Forward \(skipForward) seconds")
    }
    .foregroundStyle(SirenTheme.ink)
    .padding(.leading, 10)
    .padding(.trailing, 4)
    // The bar has a fixed height, like the tab bar under it; larger text lives in the player.
    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
  }
}
