import API
import Foundation

/// Audible's chapter names for books whose own chapters are only numbered ("Chapter 1", "01",
/// "Track 3"). Audiobookshelf looks them up on Audnexus by ASIN (`GET /api/search/chapters`) and
/// saves them to the book (`POST /api/items/:id/chapters`), which needs an account that can
/// update books. Names are saved only when Audible's timings fit the book's length.
@MainActor
public enum ChapterNames {
  /// A book whose chapters are only numbered, and what Audible has for it.
  public struct Result: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let author: String?
    public let chapterCount: Int
    public let outcome: Outcome
  }

  public enum Outcome: Sendable {
    /// Named chapters that fit the book, ready to save.
    case ready([Chapter])
    /// Audible numbers this book's chapters too.
    case noNames
    /// Audible's edition is this many seconds longer (or shorter, negative) than the book.
    case lengthDiffers(Double)
    /// Same length, but Audible's chapters start in different places, so its names wouldn't line up.
    case marksDiffer
    /// Audible has no chapters for the book's ASIN.
    case notFound
  }

  public struct Chapter: Encodable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
  }

  public struct Progress: Sendable {
    public let checked: Int
    public let total: Int
  }

  /// Books in the library with only numbered chapters and an ASIN, each looked up on Audible.
  public static func scan(
    libraryID: String,
    onProgress: @escaping @MainActor (Progress) -> Void
  ) async throws -> [Result] {
    struct Items: Decodable, Sendable { let results: [Book] }
    let items: Items = try await Audiobookshelf.shared.send(
      "/api/libraries/\(libraryID)/items",
      query: ["minified": "1"]
    )
    let books = items.results.filter { book in
      guard let asin = book.media.metadata.asin, !asin.isEmpty else { return false }
      return book.duration > 0
    }
    onProgress(Progress(checked: 0, total: books.count))

    var results: [Result] = []
    var checked = 0
    // A few at a time: each check is one or two requests, and the lookups go out to Audnexus.
    try await withThrowingTaskGroup(of: Result?.self) { group in
      var next = 0
      func add() {
        guard next < books.count else { return }
        let id = books[next].id
        next += 1
        group.addTask { try await check(id) }
      }
      for _ in 0..<4 { add() }
      while let result = try await group.next() {
        checked += 1
        onProgress(Progress(checked: checked, total: books.count))
        if let result { results.append(result) }
        add()
      }
    }
    return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  /// Saves names found by `scan`.
  public static func save(_ chapters: [Chapter], bookID: String) async throws {
    struct Body: Encodable, Sendable { let chapters: [Chapter] }
    try await Audiobookshelf.shared.send("/api/items/\(bookID)/chapters", method: .post, body: Body(chapters: chapters))
  }

  /// The book's chapters, and Audible's when they're all numbered. Nil when the book has real
  /// names already (or one chapter).
  private static func check(_ bookID: String) async throws -> Result? {
    let book: Book = try await Audiobookshelf.shared.send("/api/items/\(bookID)", query: ["expanded": "1"])
    let chapters = book.chapters ?? []
    guard chapters.count > 1, let asin = book.media.metadata.asin,
      chapters.allSatisfy({ isNumbered($0.title, bookTitle: book.title) })
    else { return nil }

    let audible: Audnexus = try await Audiobookshelf.shared.send(
      "/api/search/chapters",
      query: ["asin": asin, "region": region]
    )
    let outcome = match(
      audible,
      marks: chapters.map { (start: $0.start, end: $0.end) },
      duration: book.duration,
      bookTitle: book.title
    )
    return Result(
      id: book.id,
      title: book.title,
      author: book.media.metadata.authorName,
      chapterCount: chapters.count,
      outcome: outcome
    )
  }

  // MARK: Matching

  /// Audnexus's answer, through Audiobookshelf (`{ error }` when it has nothing).
  struct Audnexus: Decodable, Sendable {
    let chapters: [Item]?
    let runtimeLengthMs: Double?
    let brandIntroDurationMs: Double?
    let brandOutroDurationMs: Double?

    struct Item: Decodable, Sendable {
      let startOffsetMs: Double
      let lengthMs: Double
      let title: String
    }
  }

  /// How far Audible's length can be from the book's and still fit, in seconds.
  nonisolated static let tolerance: Double = 5
  /// How far each of Audible's chapter starts can be from the book's own, in seconds.
  nonisolated static let markTolerance: Double = 2

  /// Audible's names for the book's own chapters. Only titles change: the book's chapter marks
  /// stay. Audible's starts are taken as they are when the lengths agree, or moved back by
  /// Audible's intro when the file was cut without the intro and outro; then there must be as many
  /// as the book has, each within `markTolerance` of the book's.
  nonisolated static func match(
    _ audible: Audnexus,
    marks: [(start: Double, end: Double)],
    duration: Double,
    bookTitle: String
  ) -> Outcome {
    guard let items = audible.chapters, items.count > 1 else { return .notFound }
    let named = items.filter { !isNumbered($0.title, bookTitle: bookTitle) && !isCredits($0.title) }
    guard !named.isEmpty else { return .noNames }

    let length = (audible.runtimeLengthMs ?? items.last.map { $0.startOffsetMs + $0.lengthMs } ?? 0) / 1000
    let intro = (audible.brandIntroDurationMs ?? 0) / 1000
    let outro = (audible.brandOutroDurationMs ?? 0) / 1000
    let shift: Double
    if abs(duration - length) <= tolerance {
      shift = 0
    } else if intro + outro > 0, abs(duration - (length - intro - outro)) <= tolerance {
      shift = intro
    } else {
      return .lengthDiffers(length - duration)
    }

    // Audible's chapters as they fall in this file. A chapter that lay wholly inside the trimmed
    // intro (its opening credits) isn't in the file.
    var shifted: [(start: Double, title: String)] = []
    for item in items {
      let start = item.startOffsetMs / 1000 - shift
      guard start + item.lengthMs / 1000 > 0, start < duration else { continue }
      shifted.append((max(0, start), item.title))
    }
    guard shifted.count == marks.count,
      zip(shifted, marks).allSatisfy({ abs($0.start - $1.start) <= markTolerance })
    else { return .marksDiffer }
    let chapters = zip(marks, shifted).enumerated().map { index, pair in
      Chapter(id: index, start: pair.0.start, end: pair.0.end, title: pair.1.title)
    }
    return .ready(chapters)
  }

  /// "Chapter 1", "01", "Track 3", "Book Title - 07": a title that's only a number.
  nonisolated static func isNumbered(_ title: String, bookTitle: String) -> Bool {
    var text = title.lowercased()
    let book = bookTitle.lowercased()
    if !book.isEmpty { text = text.replacingOccurrences(of: book, with: " ") }
    text = text.replacing(#/[\-_.:#()\[\]]/#, with: " ")
    text = text.replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
    if text.isEmpty { return true }
    let numbered =
      #/(?:(?:chapter|chap|ch|track|part|disc|cd|kapitel|chapitre|capitulo|capítulo|capitolo|hoofdstuk)\s?)?\d+(?:\s?(?:of\s)?\d+)?/#
    return text.wholeMatch(of: numbered) != nil
  }

  /// Audible's "Opening Credits" and "End Credits": names, but not ones worth saving on their own.
  nonisolated public static func isCredits(_ title: String) -> Bool {
    let text = title.lowercased().trimmingCharacters(in: .whitespaces)
    return ["opening credits", "end credits", "credits"].contains(text)
  }

  /// Audnexus's region for the device's Audible store.
  private static var region: String {
    switch Locale.current.region?.identifier {
    case "GB", "IE": "uk"
    case "DE", "AT", "CH": "de"
    case "FR", "BE": "fr"
    case "CA": "ca"
    case "AU", "NZ": "au"
    case "IN": "in"
    case "IT": "it"
    case "ES": "es"
    case "JP": "jp"
    default: "us"
    }
  }
}
