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
  private static let spacing = Duration.milliseconds(300)

  @ObservationIgnored private var entries: [String: Entry] = [:]
  /// The batch each ASIN being fetched is in, so a second caller waits for it.
  @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private var nextRequest = ContinuousClock.now
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
    // Reserve the next slot before waiting, so batches started together still go 300 ms apart.
    let slot = max(ContinuousClock.now, nextRequest)
    nextRequest = slot + Self.spacing
    try? await Task.sleep(until: slot)

    guard let fetched = try? await Self.request(asins) else { return }
    let now = Date()
    for asin in asins {
      let rating = fetched[asin]
      entries[asin] = Entry(rating: rating, fetched: now)
      ratings[asin] = rating
    }
    scheduleSave()
  }

  nonisolated private static func request(_ asins: [String]) async throws -> [String: Rating] {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/1.0/catalog/products"
    components.queryItems = [
      URLQueryItem(name: "asins", value: asins.joined(separator: ",")),
      URLQueryItem(name: "response_groups", value: "rating"),
    ]
    guard let url = components.url else { throw URLError(.badURL) }
    let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

    struct Response: Decodable {
      let products: [Product]
    }
    struct Product: Decodable {
      let asin: String
      let rating: Ratings?
    }
    struct Ratings: Decodable {
      let overallDistribution: Distribution?
      let storyDistribution: Distribution?
      let performanceDistribution: Distribution?
    }
    struct Distribution: Decodable {
      let averageRating: Double?
      let numRatings: Int?

      /// The average, when anyone has rated it.
      var average: Double? {
        guard let averageRating, (numRatings ?? 0) > 0 else { return nil }
        return averageRating
      }
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let products = try decoder.decode(Response.self, from: data).products
    var ratings: [String: Rating] = [:]
    for product in products {
      guard let overall = product.rating?.overallDistribution, let average = overall.average else { continue }
      ratings[product.asin] = Rating(
        average: average,
        count: overall.numRatings ?? 0,
        story: product.rating?.storyDistribution?.average,
        performance: product.rating?.performanceDistribution?.average
      )
    }
    return ratings
  }

  /// The Audible store for the device's region. Each store has its own ratings.
  nonisolated private static var host: String {
    switch Locale.current.region?.identifier {
    case "GB", "IE": "api.audible.co.uk"
    case "DE", "AT", "CH": "api.audible.de"
    case "FR", "BE": "api.audible.fr"
    case "CA": "api.audible.ca"
    case "AU", "NZ": "api.audible.com.au"
    case "IN": "api.audible.in"
    case "IT": "api.audible.it"
    case "ES": "api.audible.es"
    case "JP": "api.audible.co.jp"
    case "BR": "api.audible.com.br"
    default: "api.audible.com"
    }
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
