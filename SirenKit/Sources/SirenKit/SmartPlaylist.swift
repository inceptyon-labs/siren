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
  /// When it was last saved, so two devices' edits merge instead of the later list replacing
  /// the earlier one. Nil for playlists saved before this was kept.
  public var updatedAt: Date?  // SIREN

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
    // Ties fall back to the book ID, so a limit cuts the same books every time.
    func ordered(_ key: (Book) -> Double, descending: Bool) -> [Book] {
      matching.sorted { lhs, rhs in
        let (left, right) = (key(lhs), key(rhs))
        if left != right { return descending ? left > right : left < right }
        return lhs.id < rhs.id
      }
    }
    let sorted: [Book]
    switch sort {
    case .recentlyAdded:
      sorted = ordered({ $0.addedAt.timeIntervalSince1970 }, descending: true)
    case .rating:
      sorted = ordered({ Self.rating($0, context) }, descending: true)
    case .title:
      sorted = matching.sorted { lhs, rhs in
        let order = lhs.titleIgnorePrefix.localizedStandardCompare(rhs.titleIgnorePrefix)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
      }
    case .shortest:
      sorted = ordered({ $0.duration }, descending: false)
    case .longest:
      sorted = ordered({ $0.duration }, descending: true)
    }
    return limit.map { Array(sorted.prefix($0)) } ?? sorted
  }

  static func rating(_ book: Book, _ context: Context) -> Double {
    book.media.metadata.asin.flatMap { context.ratings[$0] } ?? 0
  }

  /// One rule Audiobookshelf can apply itself, to fetch fewer books: the most selective there is.
  /// The device still checks every rule. Authors and series filter by ID, from `filterData`.
  public func serverFilter(_ filterData: FilterData?) -> String? {
    // Without the library's own names the server can't be asked: it matches exact case.
    guard let filterData else { return nil }
    /// Base64 in the URL-safe alphabet without padding: a "+" in a query reads as a space, and
    /// Audiobookshelf's decoder (Node's) takes either alphabet.
    func encoded(_ group: String, _ value: String) -> String {
      let base64 = Data(value.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      return "\(group).\(base64)"
    }
    /// The library's spelling of a name, matched ignoring case.
    func canonical(_ name: String, in names: [String]) -> String? {
      names.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    let order: [(Rule) -> String?] = [
      { rule in
        guard case .series(let name) = rule else { return nil }
        return filterData.series.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
          .map { encoded("series", $0.id) }
      },
      { rule in
        guard case .author(let name) = rule else { return nil }
        return filterData.authors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
          .map { encoded("authors", $0.id) }
      },
      { rule in
        guard case .narrator(let name) = rule else { return nil }
        return canonical(name, in: filterData.narrators).map { encoded("narrators", $0) }
      },
      { rule in
        guard case .tag(let name) = rule else { return nil }
        return canonical(name, in: filterData.tags).map { encoded("tags", $0) }
      },
      { rule in
        guard case .genre(let name) = rule else { return nil }
        return canonical(name, in: filterData.genres).map { encoded("genres", $0) }
      },
      { rule in
        guard case .language(let name) = rule else { return nil }
        return canonical(name, in: filterData.languages).map { encoded("languages", $0) }
      },
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
      return Self.listed(name, in: metadata.authorName)
    case .narrator(let name):
      return Self.listed(name, in: metadata.narratorName)
    case .series(let name):
      // "Name #1, Other #2": the name followed by its number, or by nothing.
      let joined = (metadata.seriesName ?? "").lowercased()
      let name = name.lowercased()
      guard !name.isEmpty else { return false }
      return joined.hasPrefix(name + " #") || joined.contains(", " + name + " #") || Self.listed(name, in: joined)
    case .progress(let state):
      let progress = context.progress[book.id]
      switch state {
      case .notStarted: return progress == nil || (progress?.progress == 0 && progress?.isFinished == false)
      case .inProgress: return (progress?.progress ?? 0) > 0 && progress?.isFinished == false
      case .finished: return progress?.isFinished == true
      }
    case .length(let atLeast, let atMost):
      // Books with no audio length (ebooks) aren't "under 3 hours".
      let hours = book.duration / 3600
      return book.duration > 0 && hours >= (atLeast ?? 0) && hours <= (atMost ?? .infinity)
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

  /// Whether `name` is a whole entry in Audiobookshelf's ", "-joined list. Searched rather than
  /// split, since a name can hold ", " itself ("Doe, John"), and only at entry boundaries, so
  /// "Dune" isn't "Children of Dune".
  static func listed(_ name: String, in joined: String?) -> Bool {
    let joined = (joined ?? "").lowercased()
    let name = name.trimmingCharacters(in: .whitespaces).lowercased()
    guard !name.isEmpty else { return false }
    return joined == name || joined.hasPrefix(name + ", ") || joined.hasSuffix(", " + name)
      || joined.contains(", " + name + ", ")
  }
}
