import SwiftUI

/// The full-screen player: the cover large on the left, the book, chapter and controls on the
/// right. Play/Pause on the remote works anywhere; Menu goes back and the book keeps playing.
struct TVNowPlaying: View {
  @State private var player = TVPlayer.shared
  @State private var showingChapters = false
  @FocusState private var focus: Control?

  private enum Control: Hashable { case back, playPause, forward }

  var body: some View {
    ZStack {
      SirenTheme.ground.ignoresSafeArea()
      if let book = player.book {
        HStack(alignment: .center, spacing: 80) {
          TVCover(url: book.coverURL, title: book.title)
            .frame(width: 620, height: 620)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
          details(book)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
      } else if player.isLoading {
        ProgressView()
      } else if let error = player.error {
        TVMessage(title: "Couldn't play this book", detail: error)
      }
    }
    .defaultFocus($focus, .playPause)
    .onPlayPauseCommand { player.toggle() }
    .sheet(isPresented: $showingChapters) { TVChapters() }
  }

  private func details(_ book: TVPlayer.Book) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(book.title)
        .font(SirenType.bookTitle(.title))
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(2)
      Text(book.author)
        .font(.title3)
        .foregroundStyle(SirenTheme.secondary)
      if let chapter = player.chapter {
        Text(chapter.title)
          .font(.headline)
          .foregroundStyle(SirenTheme.ink)
          .padding(.top, 12)
      }
      progress(book)
        .padding(.top, 8)
      if let error = player.error {
        Text(error)
          .font(.callout)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(2)
      }
      transport
        .padding(.top, 24)
        .focusSection()
      HStack(spacing: 32) {
        Button {
          let rates = TVPlayer.rates
          let next = rates[((rates.firstIndex(of: player.rate) ?? 0) + 1) % rates.count]
          player.setRate(next)
        } label: {
          Text(Self.rateLabel(player.rate)).monospacedDigit()
        }
        .accessibilityLabel("Speed \(Self.rateLabel(player.rate))")
        if book.chapters.count > 1 {
          Button("Chapters", systemImage: "list.bullet") { showingChapters = true }
        }
      }
      .focusSection()
    }
  }

  /// The current chapter's progress (the book's when it has no chapters), with time heard and left.
  private func progress(_ book: TVPlayer.Book) -> some View {
    let span = player.chapter.map { ($0.start, $0.end) } ?? (0, book.duration)
    let length = max(span.1 - span.0, 1)
    let heard = min(max(player.time - span.0, 0), length)
    return VStack(alignment: .leading, spacing: 10) {
      ProgressView(value: heard / length)
        .tint(SirenTheme.tint)
      HStack {
        Text(Self.clock(heard))
        Spacer()
        Text(Self.left(book.duration - player.time))
        Spacer()
        Text("−\(Self.clock(length - heard))")
      }
      .font(.callout.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(SirenTheme.secondary)
    }
  }

  private var transport: some View {
    HStack(spacing: 40) {
      Button {
        player.skip(by: -TVPlayer.skip)
      } label: {
        Image(systemName: "gobackward.30").font(.title2)
      }
      .focused($focus, equals: .back)
      .accessibilityLabel("Back 30 seconds")
      Button {
        player.toggle()
      } label: {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.title)
          .frame(width: 80)
      }
      .focused($focus, equals: .playPause)
      .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
      Button {
        player.skip(by: TVPlayer.skip)
      } label: {
        Image(systemName: "goforward.30").font(.title2)
      }
      .focused($focus, equals: .forward)
      .accessibilityLabel("Forward 30 seconds")
    }
  }

  static func rateLabel(_ rate: Float) -> String {
    rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
  }

  static func clock(_ seconds: Double) -> String {
    let total = Int(max(seconds, 0))
    let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
  }

  static func left(_ seconds: Double) -> String {
    let minutes = Int(max(seconds, 0) / 60)
    return minutes >= 60
      ? String(localized: "\(minutes / 60)h \(minutes % 60)m left in book")
      : String(localized: "\(minutes)m left in book")
  }
}

/// The book's chapters; choosing one plays from its start.
struct TVChapters: View {
  @State private var player = TVPlayer.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List(player.book?.chapters ?? []) { chapter in
        Button {
          player.seek(to: chapter.start)
          dismiss()
        } label: {
          HStack {
            Text(chapter.title)
              .foregroundStyle(chapter == player.chapter ? SirenTheme.tint : SirenTheme.ink)
            Spacer()
            Text(TVNowPlaying.clock(chapter.end - chapter.start))
              .monospacedDigit()
              .foregroundStyle(SirenTheme.secondary)
          }
        }
      }
      .navigationTitle("Chapters")
    }
  }
}
