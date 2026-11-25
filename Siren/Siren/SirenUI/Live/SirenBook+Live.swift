import API
import Foundation
import Models

// Builds `SirenBook` values from upstream's view models, so the Siren screens draw real books.

extension SirenBook {
  init(id: String, title: String, author: String?, coverURL: URL?) {
    let author = author ?? ""
    self.init(
      id: id,
      title: title,
      author: author,
      cover: .placeholder(id: id, title: title, author: author),
      coverURL: coverURL
    )
  }

  /// A library, shelf or Continue Listening card.
  init(card: BookCard.Model) {
    self.init(id: card.id, title: card.title, author: card.author, coverURL: card.cover.url)
    narrator = card.narrator ?? ""
    progress = card.cover.progress ?? 0
    seriesIndex = card.sequence.flatMap { Int($0) }
    if let remaining = card.timeRemaining, progress > 0 {
      timeLeft = SirenFormat.span(remaining)
    } else if let remaining = card.timeRemaining {
      hours = remaining / 3600
    }
  }

  /// A series tile: its first cover, its name and how many books it has.
  init(series: SeriesCard.Model) {
    self.init(
      id: series.id,
      title: series.title,
      author: series.bookCount == 1 ? "1 book" : "\(series.bookCount) books",
      coverURL: series.bookCovers.first?.url
    )
    progress = series.progress ?? 0
  }

  /// The book in the player, with its real chapters.
  init(player: BookPlayer.Model) {
    self.init(id: player.id, title: player.title, author: player.author, coverURL: player.coverURL)
    let playback = player.playbackProgress
    progress = playback.totalProgress
    hours = playback.total / 3600
    timeLeft = SirenFormat.span(playback.totalTimeRemaining)
    if let chapters = player.chapters, chapters.chapters.count > 1 {
      chapterCount = chapters.chapters.count
      currentChapter = chapters.currentIndex + 1
      chapterTitle = chapters.current?.title ?? ""
      chapterMarks = Self.marks(chapters.chapters.map(\.start), total: playback.total)
      if let chapter = playback.chapter {
        chapterProgress = chapter.progress
        chapterRemaining = SirenFormat.clock(chapter.remaining)
      }
    }
  }

  /// Adds chapter position from a fetched book and its saved progress.
  mutating func apply(chapters: [Book.Media.Chapter], currentTime: TimeInterval, duration: TimeInterval) {
    guard chapters.count > 1, duration > 0 else { return }
    chapterCount = chapters.count
    chapterMarks = Self.marks(chapters.map(\.start), total: duration)
    let index = chapters.lastIndex { $0.start <= currentTime } ?? 0
    let chapter = chapters[index]
    currentChapter = index + 1
    chapterTitle = chapter.title
    let length = max(chapter.end - chapter.start, 1)
    chapterProgress = min(max((currentTime - chapter.start) / length, 0), 1)
    chapterRemaining = SirenFormat.clock(max(chapter.end - currentTime, 0))
  }

  static func marks(_ starts: [TimeInterval], total: TimeInterval) -> [Double]? {
    guard total > 0 else { return nil }
    return starts.map { min(max($0 / total, 0), 1) }
  }
}

enum SirenCovers {
  /// Cover of a library item when only its ID is known (year stats, saved progress).
  @MainActor static func url(itemID: String) -> URL? {
    Audiobookshelf.shared.serverURL?.appendingPathComponent("api/items/\(itemID)/cover")
  }
}
