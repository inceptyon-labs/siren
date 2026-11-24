import Foundation

/// What a Siren screen needs to draw a book. Demo data builds these directly; the live screens
/// build them from upstream's view models.
struct SirenBook: Identifiable, Hashable {
  let id: String
  let title: String
  let author: String
  var narrator = ""
  var series: String?
  var seriesIndex: Int?
  var hours: Double = 0
  /// 0...1 of the whole book heard.
  var progress: Double = 0
  var chapterCount = 0
  var currentChapter = 1
  var chapterTitle = ""
  var chapterProgress: Double = 0
  var chapterRemaining = ""
  var timeLeft = ""
  var rating: Double = 0
  var ratingCount = 0
  var genre = ""
  /// Drawn jacket: the whole cover in demo data, the fallback when a server cover is missing.
  var cover: CoverSpec
  /// The server's cover. When set, it replaces the drawn jacket.
  var coverURL: URL?
  /// Start of each chapter as a fraction of the book, when the real chapters are known.
  var chapterMarks: [Double]?
  var request: DemoRequestStatus?
  var releaseDate: String?
  var finishedOn: String?
  var inLibrary = true

  var isFinished: Bool { progress >= 1 }
  var isStarted: Bool { progress > 0 }

  /// Start of each chapter as a fraction of the book, for the reveal's tick marks.
  var chapterStarts: [Double] {
    if let chapterMarks { return chapterMarks }
    guard chapterCount > 1 else { return [0] }
    if id == Demo.saltRoad.id {
      // Long opening chapters, shorter ones later: chapter 14 starts at 0.55.
      let early = (0..<13).map { Double($0) * 0.55 / 13 }
      let late = (0..<(chapterCount - 13)).map { 0.55 + Double($0) * 0.45 / Double(chapterCount - 13) }
      return early + late
    }
    return (0..<chapterCount).map { Double($0) / Double(chapterCount) }
  }
}
