import Foundation

/// A series on Audible, every book in it whether you have it or not, in order.
public struct AudibleSeriesList: Codable, Sendable, Hashable {
  public let asin: String
  public let title: String
  public let books: [Book]

  public struct Book: Codable, Sendable, Hashable, Identifiable {
    public let product: AudibleProduct
    /// Audible's position: "1", "3.5".
    public let sequence: String

    public var id: String { product.asin }
    public var position: Double { Double(sequence) ?? .infinity }

    /// Nil when Audible has no real date (it uses 2200-01-01 for "unknown").
    public var releaseDate: Date? {
      guard let text = product.releaseDate, let date = AudibleSeries.dayFormat.date(from: text),
        date < AudibleSeries.unknownDate
      else { return nil }
      return date
    }

    public var isUpcoming: Bool { releaseDate.map { $0 > .now } ?? false }
  }
}

/// Audible's series: which one a book is in, and every book in it with its release date. Series
/// are cached for 3 days (release dates move), which series a book is in for 30.
@MainActor
public final class AudibleSeries {
  public static let shared = AudibleSeries()

  private struct Cache: Codable {
    /// Book ASIN and series name to the series ASIN chosen for it ("" when it's in none).
    var seriesOf: [String: Stamped<String>] = [:]
    var series: [String: Stamped<AudibleSeriesList>] = [:]
  }

  private struct Stamped<Value: Codable & Sendable>: Codable, Sendable {
    let value: Value
    let fetched: Date

    func isFresh(_ maxAge: TimeInterval) -> Bool { Date().timeIntervalSince(fetched) < maxAge }
  }

  private static let seriesOfAge: TimeInterval = 30 * 24 * 3600
  private static let seriesAge: TimeInterval = 3 * 24 * 3600

  nonisolated static let dayFormat: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(identifier: "UTC")
    format.dateFormat = "yyyy-MM-dd"
    return format
  }()
  nonisolated static let unknownDate = dayFormat.date(from: "2100-01-01") ?? .distantFuture

  private var cache = Cache()
  private var pendingSave: Task<Void, Never>?
  private let cacheFile = URL.cachesDirectory.appending(path: "audible-series.json")

  private init() {
    if let data = try? Data(contentsOf: cacheFile), let saved = try? JSONDecoder().decode(Cache.self, from: data) {
      cache = saved
    }
  }

  /// The series this book is in on Audible. When it's in several (a saga inside a universe),
  /// the one whose name matches `name` (Audiobookshelf's), else the first that numbers it.
  public func series(ofBook asin: String, named name: String?) async -> AudibleSeriesList? {
    let seriesASIN: String
    // A book in several series maps to a different one depending on the name asked for.
    let key = "\(asin)|\(name.map(Self.normalized) ?? "")"
    if let known = cache.seriesOf[key], known.isFresh(Self.seriesOfAge) {
      seriesASIN = known.value
    } else {
      guard let found = await findSeries(ofBook: asin, named: name) else { return nil }
      seriesASIN = found
      cache.seriesOf[key] = Stamped(value: found, fetched: Date())
      scheduleSave()
    }
    guard !seriesASIN.isEmpty else { return nil }
    if let known = cache.series[seriesASIN], known.isFresh(Self.seriesAge) {
      return known.value
    }
    guard let list = await loadSeries(seriesASIN) else { return nil }
    cache.series[seriesASIN] = Stamped(value: list, fetched: Date())
    scheduleSave()
    return list
  }

  // MARK: Requests

  private struct SeriesRef: Decodable {
    let asin: String
    let title: String?
    let sequence: String?
  }

  /// The series ASIN for a book, "" when it's in none; nil when Audible couldn't be reached.
  private func findSeries(ofBook asin: String, named name: String?) async -> String? {
    struct Response: Decodable {
      struct Product: Decodable { let series: [SeriesRef]? }
      let product: Product
    }
    guard
      let data = try? await AudibleCatalog.get(
        "catalog/products/\(asin)",
        query: [URLQueryItem(name: "response_groups", value: "series")]
      ),
      let response = try? AudibleCatalog.decoder().decode(Response.self, from: data)
    else { return nil }
    let all = response.product.series ?? []
    let wanted = name.map(Self.normalized)
    let named = all.first { ref in
      guard let wanted, !wanted.isEmpty, let title = ref.title.map(Self.normalized) else { return false }
      return title == wanted || title.contains(wanted) || wanted.contains(title)
    }
    let numbered = all.first { !($0.sequence ?? "").isEmpty }
    return (named ?? numbered ?? all.first)?.asin ?? ""
  }

  private func loadSeries(_ asin: String) async -> AudibleSeriesList? {
    struct Response: Decodable {
      struct Product: Decodable {
        let title: String?
        let relationships: [Relationship]?
      }
      struct Relationship: Decodable {
        let asin: String
        let relationshipToProduct: String?
        let relationshipType: String?
        let sequence: String?
      }
      let product: Product
    }
    guard
      let data = try? await AudibleCatalog.get(
        "catalog/products/\(asin)",
        query: [URLQueryItem(name: "response_groups", value: "relationships,product_desc")]
      ),
      let response = try? AudibleCatalog.decoder().decode(Response.self, from: data)
    else { return nil }

    // Numbered members only: unnumbered ones are collections and companions.
    var sequenceOf: [String: String] = [:]
    for member in response.product.relationships ?? []
    where member.relationshipToProduct == "child" && member.relationshipType == "series" {
      guard let sequence = member.sequence, Double(sequence) != nil else { continue }
      sequenceOf[member.asin] = sequence
    }
    guard !sequenceOf.isEmpty else {
      return AudibleSeriesList(asin: asin, title: response.product.title ?? "", books: [])
    }

    var products: [AudibleProduct] = []
    let asins = Array(sequenceOf.keys)
    for start in stride(from: 0, to: asins.count, by: 50) {
      guard let batch = await AudibleProducts.lookup(Array(asins[start..<min(start + 50, asins.count)])) else {
        return nil
      }
      products += batch
    }

    // Audible lists every edition; keep the most-rated one at each position.
    var best: [String: AudibleSeriesList.Book] = [:]
    for product in products {
      guard let sequence = sequenceOf[product.asin], let position = Double(sequence) else { continue }
      let book = AudibleSeriesList.Book(product: product, sequence: sequence)
      let key = String(position)
      if let current = best[key], Self.rank(current) >= Self.rank(book) { continue }
      best[key] = book
    }
    let books = best.values.sorted { $0.position < $1.position }
    return AudibleSeriesList(asin: asin, title: response.product.title ?? "", books: books)
  }

  /// More ratings wins; then a real release date over Audible's placeholder.
  private static func rank(_ book: AudibleSeriesList.Book) -> (Int, Int) {
    (book.product.rating?.count ?? 0, book.releaseDate == nil ? 0 : 1)
  }

  static func normalized(_ text: String) -> String {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0 != "the" && $0 != "a" }
      .joined(separator: " ")
  }

  private func scheduleSave() {
    pendingSave?.cancel()
    pendingSave = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let data = try? JSONEncoder().encode(cache) else { return }
      let file = cacheFile
      Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
    }
  }
}
