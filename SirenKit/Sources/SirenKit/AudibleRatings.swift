import Foundation
import Observation

/// Audible's star ratings by ASIN, from Audible's catalog API, which needs no sign-in.
/// Audiobookshelf keeps each book's ASIN but not its rating. Ratings are cached on the device for
/// 14 days, and requests go 50 ASINs at a time (Audible's limit), at least 300 ms apart.
///
/// The catalog API is undocumented. When a request fails, those books show no rating and are
/// asked for again next time.
@MainActor @Observable
public final class AudibleRatings {
  public static let shared = AudibleRatings()

  public struct Rating: Codable, Sendable, Hashable {
    public let average: Double
    public let count: Int
    public let story: Double?
    public let performance: Double?
  }

  /// Ratings loaded so far, by ASIN. Books Audible has no ratings for aren't here.
  public private(set) var ratings: [String: Rating] = [:]

  private struct Entry: Codable {
    /// Nil when Audible has no ratings for the book.
    let rating: Rating?
    let fetched: Date
  }

  private static let maxAge: TimeInterval = 14 * 24 * 3600
  private static let batchSize = 50

  @ObservationIgnored private var entries: [String: Entry] = [:]
  /// The batch each ASIN being fetched is in, so a second caller waits for it.
  @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  private let cacheFile = URL.cachesDirectory.appending(path: "audible-ratings.json")

  private init() {
    loadCache()
  }

  public func rating(for asin: String?) -> Rating? {
    asin.flatMap { ratings[$0] }
  }

  /// Loads the ratings of these books, from the cache when it's fresh. Returns once they're in
  /// `ratings`, or once the request for them has failed.
  public func load(_ asins: some Sequence<String>) async {
    let now = Date()
    var waits: [Task<Void, Never>] = []
    var missing: [String] = []
    for asin in Set(asins) where !asin.isEmpty {
      if let entry = entries[asin], now.timeIntervalSince(entry.fetched) < Self.maxAge { continue }
      if let batch = inFlight[asin] {
        waits.append(batch)
      } else {
        missing.append(asin)
      }
    }
    for start in stride(from: 0, to: missing.count, by: Self.batchSize) {
      let batch = Array(missing[start..<min(start + Self.batchSize, missing.count)])
      let task = Task { await self.fetch(batch) }
      for asin in batch { inFlight[asin] = task }
      waits.append(task)
    }
    for task in Set(waits) { await task.value }
  }

  // MARK: Network

  private func fetch(_ asins: [String]) async {
    defer { for asin in asins { inFlight[asin] = nil } }
    guard
      let data = try? await AudibleCatalog.get(
        "catalog/products",
        query: [
          URLQueryItem(name: "asins", value: asins.joined(separator: ",")),
          URLQueryItem(name: "response_groups", value: "rating"),
        ]
      ),
      let response = try? AudibleCatalog.decoder().decode(Response.self, from: data)
    else { return }
    let fetched = Dictionary(
      response.products.map { ($0.asin, $0.rating?.rating) },
      uniquingKeysWith: { first, _ in first }
    )
    let now = Date()
    for asin in asins {
      let rating = fetched[asin] ?? nil
      entries[asin] = Entry(rating: rating, fetched: now)
      ratings[asin] = rating
    }
    scheduleSave()
  }

  private struct Response: Decodable {
    struct Product: Decodable {
      let asin: String
      let rating: AudibleCatalog.RawRatings?
    }
    let products: [Product]
  }

  // MARK: Cache

  private func loadCache() {
    guard let data = try? Data(contentsOf: cacheFile),
      let saved = try? JSONDecoder().decode([String: Entry].self, from: data)
    else { return }
    let now = Date()
    entries = saved.filter { now.timeIntervalSince($0.value.fetched) < Self.maxAge }
    ratings = entries.compactMapValues(\.rating)
  }

  /// Saves a second after the last batch, so a library-wide load writes the file once or twice.
  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let data = try? JSONEncoder().encode(entries) else { return }
      let file = cacheFile
      Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
    }
  }
}
