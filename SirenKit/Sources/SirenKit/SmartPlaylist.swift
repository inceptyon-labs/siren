import API
import Foundation

/// A playlist defined by rules instead of picked books. A book is in it when it matches every
/// rule. Definitions sync through iCloud (`SmartPlaylists`); the books are worked out on the
/// device each time.
public struct SmartPlaylist: Codable, Identifiable, Hashable, Sendable {
  public var id = UUID()
  public var name: String
  public var rules: [Rule]
  public var sort: Sort = .recentlyAdded
  /// At most this many books; nil for all.
  public var limit: Int?

  public init(name: String, rules: [Rule] = [], sort: Sort = .recentlyAdded, limit: Int? = nil) {
    self.name = name
    self.rules = rules
    self.sort = sort
    self.limit = limit
  }

  public enum Rule: Codable, Hashable, Sendable {
    case genre(name: String)
    case tag(name: String)
    case author(name: String)
    case narrator(name: String)
    case series(name: String)
    case progress(Progress)
    /// Hours; either bound may be open.
    case length(atLeast: Double?, atMost: Double?)
    /// Audible's rating, as Audible rounds it.
    case rating(atLeast: Double)
    case addedWithin(days: Int)
    case language(name: String)
    case explicit(Bool)
  }

  public enum Progress: String, Codable, CaseIterable, Sendable {
    case notStarted, inProgress, finished
  }

  public enum Sort: String, Codable, CaseIterable, Sendable {
    case recentlyAdded, rating, title, shortest, longest
  }

  /// Whether the books need Audible ratings.
  public var usesRatings: Bool {
    sort == .rating || rules.contains { if case .rating = $0 { true } else { false } }
  }
}

// MARK: Evaluation

extension SmartPlaylist {
  /// What a rule needs to know about a book besides the book.
  public struct Context: Sendable {
    /// Book ID to (0...1, finished).
    public var progress: [String: (progress: Double, isFinished: Bool)]
    /// ASIN to Audible's average.
    public var ratings: [String: Double]
    public var now: Date

    public init(progress: [String: (progress: Double, isFinished: Bool)], ratings: [String: Double], now: Date = .now) {
      self.progress = progress
      self.ratings = ratings
      self.now = now
    }
  }

  /// The books that match every rule, sorted and limited.
  public func books(from library: [Book], context: Context) -> [Book] {
    let matching = library.filter { book in rules.allSatisfy { $0.matches(book, context) } }
    let sorted: [Book]
    switch sort {
    case .recentlyAdded:
      sorted = matching.sorted { $0.addedAt > $1.addedAt }
    case .rating:
      sorted = matching.sorted { Self.rating($0, context) > Self.rating($1, context) }
    case .title:
      sorted = matching.sorted {
        $0.titleIgnorePrefix.localizedStandardCompare($1.titleIgnorePrefix) == .orderedAscending
      }
    case .shortest:
      sorted = matching.sorted { $0.duration < $1.duration }
    case .longest:
      sorted = matching.sorted { $0.duration > $1.duration }
    }
    return limit.map { Array(sorted.prefix($0)) } ?? sorted
  }

  static func rating(_ book: Book, _ context: Context) -> Double {
    book.media.metadata.asin.flatMap { context.ratings[$0] } ?? 0
  }

  /// One rule Audiobookshelf can apply itself, to fetch fewer books: the most selective there is.
  /// The device still checks every rule. Authors and series filter by ID, from `filterData`.
  public func serverFilter(_ filterData: FilterData?) -> String? {
    func encoded(_ group: String, _ value: String) -> String {
      "\(group).\(Data(value.utf8).base64EncodedString())"
    }
    let order: [(Rule) -> String?] = [
      { rule in
        guard case .series(let name) = rule else { return nil }
        return filterData?.series.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
          .map { encoded("series", $0.id) }
      },
      { rule in
        guard case .author(let name) = rule else { return nil }
        return filterData?.authors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
          .map { encoded("authors", $0.id) }
      },
      { if case .narrator(let name) = $0 { encoded("narrators", name) } else { nil } },
      { if case .tag(let name) = $0 { encoded("tags", name) } else { nil } },
      { if case .genre(let name) = $0 { encoded("genres", name) } else { nil } },
      { if case .language(let name) = $0 { encoded("languages", name) } else { nil } },
    ]
    for pick in order {
      if let filter = rules.lazy.compactMap(pick).first { return filter }
    }
    return nil
  }
}

extension SmartPlaylist.Rule {
  func matches(_ book: Book, _ context: SmartPlaylist.Context) -> Bool {
    let metadata = book.media.metadata
    switch self {
    case .genre(let name):
      return (metadata.genres ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    case .tag(let name):
      return (book.tags ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    case .author(let name):
      return Self.names(metadata.authorName).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    case .narrator(let name):
      return Self.names(metadata.narratorName).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    case .series(let name):
      // "Name #1, Other #2", searched rather than split: a series name can contain ", ".
      let joined = (metadata.seriesName ?? "").lowercased()
      let name = name.lowercased()
      return joined.contains("\(name) #") || joined == name || joined.hasPrefix("\(name), ")
        || joined.hasSuffix(", \(name)") || joined.contains(", \(name), ")
    case .progress(let state):
      let progress = context.progress[book.id]
      switch state {
      case .notStarted: return progress == nil || (progress?.progress == 0 && progress?.isFinished == false)
      case .inProgress: return (progress?.progress ?? 0) > 0 && progress?.isFinished == false
      case .finished: return progress?.isFinished == true
      }
    case .length(let atLeast, let atMost):
      let hours = book.duration / 3600
      return hours >= (atLeast ?? 0) && hours <= (atMost ?? .infinity)
    case .rating(let atLeast):
      // As Audible shows it: 4.46 reads as 4.5.
      return (SmartPlaylist.rating(book, context) * 10).rounded() / 10 >= atLeast
    case .addedWithin(let days):
      return book.addedAt >= context.now.addingTimeInterval(-Double(days) * 86_400)
    case .language(let name):
      return metadata.language?.caseInsensitiveCompare(name) == .orderedSame
    case .explicit(let isExplicit):
      return (metadata.explicit ?? false) == isExplicit
    }
  }

  static func names(_ joined: String?) -> [String] {
    (joined ?? "").components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
