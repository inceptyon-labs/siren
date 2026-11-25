import Foundation
import Models

/// The voice print's ridges for a downloaded book: each chapter's loudness, read from its files by
/// `SirenAudioScan`. Streamed books have none: their audio can't be read ahead of playback.
@MainActor
enum SirenVoicePrint {
  /// A downloaded book's files, in order, and its chapters, in the book's seconds.
  struct Source: Equatable {
    struct File: Equatable {
      let url: URL
      let start: Double
    }
    let files: [File]
    let chapters: [Range<Double>]
  }

  static func source(bookID: String) -> Source? {
    guard let book = try? LocalBook.fetch(bookID: bookID), book.isDownloaded else { return nil }
    var files: [Source.File] = []
    for track in book.tracks.sorted(by: { $0.index < $1.index }) {
      guard let url = track.localPath else { return nil }
      files.append(Source.File(url: url, start: track.startOffset))
    }
    let chapters = book.chapters.sorted { $0.start < $1.start }.map { $0.start..<max($0.end, $0.start + 1) }
    guard !files.isEmpty, !chapters.isEmpty else { return nil }
    return Source(files: files, chapters: chapters)
  }

  /// `samples` heights (0–1) per chapter; nil for a chapter not read yet. Narration is about as
  /// loud all the way through, so ordinary speech sits a quarter of the way up, louder passages
  /// rise above it and pauses fall to the line, scaled across the whole book.
  static func ridges(_ source: Source, samples: Int) -> [[Double]?] {
    let loudness = source.files.map { SirenAudioScan.shared.loudness(in: $0.url) }
    let raw: [[Double]?] = source.chapters.map { chapter in
      var ridge: [Double] = []
      let step = (chapter.upperBound - chapter.lowerBound) / Double(samples)
      for i in 0..<samples {
        let time = chapter.lowerBound + step * Double(i)
        guard let level = level(from: time, to: time + step, in: source.files, loudness) else { return nil }
        ridge.append(level)
      }
      return ridge
    }
    let all = raw.compactMap { $0 }.flatMap { $0 }.sorted()
    guard all.count > 1 else { return raw }
    let floor = all[all.count / 20]
    let speech = all[all.count / 2]
    let top = all[min(all.count - 1, all.count * 99 / 100)]
    func height(_ level: Double) -> Double {
      if level <= speech { return 0.25 * min(max((level - floor) / max(speech - floor, 1), 0), 1) }
      return 0.25 + 0.75 * pow(min(max((level - speech) / max(top - speech, 1), 0), 1), 1.2)
    }
    return raw.map { ridge in
      ridge.map { levels in
        let heights = levels.map(height)
        // A light blur, like ink on paper.
        return heights.indices.map { i in
          let near = heights[max(0, i - 1)...min(heights.count - 1, i + 1)]
          return near.reduce(0, +) / Double(near.count)
        }
      }
    }
  }

  /// The mean level (dBFS) from `start` to `end` of the book, or nil if not read yet.
  private static func level(
    from start: Double,
    to end: Double,
    in files: [Source.File],
    _ loudness: [[Float?]?]
  ) -> Double? {
    guard let index = files.lastIndex(where: { $0.start <= start }), let bins = loudness[index] else { return nil }
    let offset = files[index].start
    let first = Int((start - offset) / SirenAudioScan.bin)
    let last = max(first, Int(((end - offset) / SirenAudioScan.bin).rounded(.up)) - 1)
    guard first < bins.count else { return nil }
    var sum = 0.0
    var count = 0
    for bin in first...min(last, bins.count - 1) {
      guard let level = bins[bin] else { return nil }
      sum += Double(level)
      count += 1
    }
    return count > 0 ? sum / Double(count) : nil
  }
}
